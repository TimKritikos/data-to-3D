#!/bin/sh

#  data-to-3D.sh -- POSIX shell script to combine open source tools for reconstruction of 3d models
#
#   Copyright 2025 Efthymios Kritikos
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <https://www.gnu.org/licenses/>.  */

set -eu

#TODO make it add escape sequencies so that a posix shell would re-interpret it as the same arguments
CMD_LINE="$0 $*"

VERSION="v0.0-dev"
TECHNOLOGIES="using Colmap OpenMVS and ACVD"

#TODO remove unasigned faces in openmvs instead of coloring them a specific color
#TODO investigate pixel perfect photogrammetry paper

#################
## Set defaults
#################
CLEAN_WORK_DIR=1
WORKSPACE=
WORKSPACE_SET=0
ACTION=calculate
IMAGE_DIR=
OUTPUT_DIR=
MASK_DIR=
MASK_DIR_SET=0
QUALITY_SETTING=best_quality
#DELETE-ME-ON-RELEASE
UNSTABLE_WARNED=0

#################
## Parse command line options
#################
while [ "$#" -gt 0 ]
do
	case $1 in
		-v|--version)
			echo "$VERSION"
			exit 0
			;;
		-i|--input)
			shift
			IMAGE_DIR=$1
			;;
		-m|--mask)
			shift
			MASK_DIR=$1
			MASK_DIR_SET=1
			;;
		-o|--output)
			shift
			OUTPUT_DIR=$1
			;;
		-h|--help)
			ACTION=help
			;;
		-d|--workspace-dir)
			shift
			WORKSPACE=$(realpath "$1")/
			WORKSPACE_SET=1
			;;
		-n|--dont-clean-work-dir)
			CLEAN_WORK_DIR=0
			;;

		-q|--quality)
			shift
			QUALITY_SETTING=$1
			;;
		#DELETE-ME-ON-RELEASE
		--run-unstable)
			UNSTABLE_WARNED=1
			;;
		*)
			echo "Unknown option $1"
			ACTION=help-error
			break
			;;
	esac
	shift
done

#################
## Sanity check & set more defaults
#################

if [ "$WORKSPACE_SET" = 0 ]
then
	WORKSPACE=$(mktemp -d /tmp/tmp.data23d.XXXXX )
fi

if ! [ "$ACTION" = help ]
then
	#DELETE-ME-ON-RELEASE
	if [ "$UNSTABLE_WARNED" = 0 ]
	then
		echo !!CAUTION!!
		echo This program is unstable, meaning the output, input parameters, input data and function of the program can change!
		echo If you still want to run the program you need to add the parameter --run-unstable
		echo
		ACTION=help-error
	fi
	if ! [ -d "$WORKSPACE" ]
	then
		echo ERROR: Set workspace dir \""$WORKSPACE"\" doens\'t exist
		echo
		ACTION=help-error
	elif ! [ "$(find "$WORKSPACE" -mindepth 1)" = "" ]
	then
		echo ERROR: Workspace dir \""$WORKSPACE"\" isn\'t empty
		echo
		ACTION=help-error
	fi

	if [ "$IMAGE_DIR" = "" ] || [ "$OUTPUT_DIR" = "" ] || ! [ -d "$IMAGE_DIR" ] || ! [ -d "$OUTPUT_DIR" ]
	then
		echo ERROR: Input or output directories not set or don\'t point to a valid directory
		echo
		ACTION=help-error
	elif ! [ "$(find "$OUTPUT_DIR" -mindepth 1)" = "" ] && ! [ "$ACTION" = help ]
	then
		echo ERROR: Output dir not empty
		echo
		ACTION=help-error
	fi

	if ! [ "$QUALITY_SETTING" = "best_quality" ] && ! [ "$QUALITY_SETTING" = "litest_resources" ]
	then
		echo ERROR: Invalid quality setting \""$QUALITY_SETTING"\"
		echo
		ACTION=help-error
	fi
	if [ "$MASK_DIR_SET" = 1 ]
	then
		if ! [ -d "$MASK_DIR" ]
		then
			echo ERROR: Set mask dir doesn\'t exist
			echo
			ACTION=help-error
		fi
	fi
fi


#################
## Error out if necessary
#################

if [ "$ACTION" = "help" ] || [ "$ACTION" = "help-error" ]
then
	##########################################################################
	#### WARNING: command line options might not be sanity checked here ######
	##########################################################################

#DELETE-ME-ON-RELEASE
	printf \
'   Usage: %s [options]\n'\
'\n'\
'Options:\n'\
' --input -i                Specify the directory of input files\n'\
'                             [%s]\n'\
' --output -o               Specify the directory for output files to be written\n'\
'                             [%s]\n'\
' --mask -m                 Specify a directory with mask images of the same\n'\
'                            name as in the input direcotry but with a ".png"\n'\
'                            appended. All black pixels on those images will be \n'\
'                            ignored on the input images\n'\
'                             [%s]\n'\
' --dont-clean-work-dir -n  Don'"'"'t delete the files inside the workspace\n'\
'                            direcotry after successful completion\n'\
' --version -v              Prints the script version and exit\n'\
'                             [%s]\n'\
' --workspace-dir -d        Set the workspace direcotry. Depending on the input\n'\
'                            resolution this could grow to hundreds of gibibytes\n'\
'                             [%s]\n'\
' --quality -q              Set the quality setting. This can take one of the \n'\
'                            following options:\n'\
'                            \"best_quality\"      Create the highest quality\n'\
'                                                models with no regards to\n'\
'                                                resource utilisation\n'\
'                            \"litest_resources\"  Utiles the least amount of\n'\
'                                                resources with no regards to\n'\
'                                                model quality\n'\
'                             [%s]\n'\
' --run-unstable            You need to pass this parameter since the program is\n'\
'                            still unstable\n'\
' -h --help                 Print this help message\n' \
"$0" "$IMAGE_DIR" "$OUTPUT_DIR" "$MASK_DIR" "$VERSION" "$WORKSPACE" "$QUALITY_SETTING"

	if [ "$WORKSPACE_SET" = 0 ]
	then
		rmdir "$WORKSPACE"
	fi

	if [ "$ACTION" = "help-error" ]
	then
		exit 1
	else
		exit 0
	fi
fi

#################
## Process data
#################

IMAGE_DIR=$(realpath "$IMAGE_DIR")
OUTPUT_DIR=$(realpath "$OUTPUT_DIR")

if [ "$CLEAN_WORK_DIR" = 0 ] && [ "$WORKSPACE_SET" = 0 ]
then
	echo Using workspace dir \""$WORKSPACE"\"  | tee -a "$WORKSPACE"/log
fi

DATA=multi_camera
TYPE=

if [ -e config.sh ]
then
	#shellcheck disable=SC1091
	. ./config.sh
fi

COLMAP_OPTS=

case "$DATA" in
	"single_camera")
		COLMAP_OPTS="$COLMAP_OPTS --single_camera=1"
		;;
	*)
		COLMAP_OPTS="$COLMAP_OPTS --single_camera=0"
		;;
esac

case "$TYPE" in
	"photos")
		COLMAP_OPTS="$COLMAP_OPTS --data_type=individual"
		;;
	*)
		;;
esac

PICTURES_NUM=$(find "$IMAGE_DIR" | grep '\.jpg$\|\.png$' -c )

if [ "$PICTURES_NUM" = 0 ]
then
	echo Error: no images found  | tee -a "$WORKSPACE"/log
	exit 1
fi

SEED=$(shuf -i 1-1000 -n 1)

echo Photogrammetry script version "$VERSION" "$TECHNOLOGIES" | tee -a "$WORKSPACE"/log
echo Using "$PICTURES_NUM" pictures and seed "$SEED"  | tee -a "$WORKSPACE"/log

mkdir "$WORKSPACE"/colmap "$WORKSPACE"/openmvs

COLMAP=colmap

print_time(){
	ELAPSED_TIME=$1
	if [ "$ELAPSED_TIME" -lt 60 ]
	then
		printf '[ took %ss ]\n' "$ELAPSED_TIME"
	elif [ "$ELAPSED_TIME" -lt 3600 ]
	then
		printf '[ took %sm %ss ]\n'  $((ELAPSED_TIME%3600/60)) $((ELAPSED_TIME%60))
	else
		printf '[ took %sh %sm %ss ]\n' $((ELAPSED_TIME/3600)) $((ELAPSED_TIME%3600/60)) $((ELAPSED_TIME%60))
	fi
}

printf '(colmap) Generating sparse and dense point clouds '
START=$(date +%s)

if [ "$QUALITY_SETTING" = "best_quality" ]
then
	COLMAP_QUALITY="--quality=extreme"
elif [ "$QUALITY_SETTING" = "litest_resources" ]
then
	COLMAP_QUALITY="--quality=medium"
else
	echo INTERNAL_ERROR | tee -a "$WORKSPACE"/log
	exit 1
fi

#shellcheck disable=SC2086
if [ "$MASK_DIR_SET" = 1 ]
then
echo using mask
	"$COLMAP" automatic_reconstructor \
		--workspace_path "$WORKSPACE"/colmap\
		--image_path "$IMAGE_DIR" \
		--mask_path "$MASK_DIR" \
		$COLMAP_OPTS \
		"$COLMAP_QUALITY" \
		--sparse=1 \
		--dense=1 \
		--num_threads=-1 \
		--log_to_stderr 1 \
		--mesher=poisson \
		--random_seed="$SEED" >> "$WORKSPACE"/log 2>>"$WORKSPACE"/log
else
	"$COLMAP" automatic_reconstructor \
		--workspace_path "$WORKSPACE"/colmap\
		--image_path "$IMAGE_DIR" \
		$COLMAP_OPTS \
		"$COLMAP_QUALITY" \
		--sparse=1 \
		--dense=1 \
		--num_threads=-1 \
		--log_to_stderr 1 \
		--mesher=poisson \
		--random_seed="$SEED" >> "$WORKSPACE"/log 2>>"$WORKSPACE"/log
fi
END=$(date +%s)
print_time "$((END-START))"

#echo Running model_converter >> work/log
#"$COLMAP" model_converter \
#	--random_seed "$SEED" \
#	--log_to_stderr 1 \
#	--input_path ./work/dense/"$DENSEST"/sparse/ \
#	--output_type Bundler \
#	--output_path work/bundler_conv_out  >>work/log 2>>work/log

MODELS=$(find "$WORKSPACE"/colmap/dense/ -mindepth 1 -maxdepth 1 | wc -l)

printf 'Colmap generated %s model' "$MODELS" | tee -a "$WORKSPACE"/log
if [ "$MODELS" = 1 ]
then
	printf '\n' | tee -a "$WORKSPACE"/log
else
	printf 's\n' | tee -a "$WORKSPACE"/log
fi

#OpenMVS x64 v2.3.0 has a bug were it miscalculates the image path in ReconstructMesh if the current directory isn't the working folder of openmvs
cd "$WORKSPACE/openmvs"

ALL_REST_STEPS=7
if [ "$QUALITY_SETTING" = "best_quality" ]
then
	ALL_REST_STEPS=$((ALL_REST_STEPS+1)) # Add the refining step
fi

for i in $(seq "$MODELS" )
do
	STEP_N=1
	MODEL_NUMBER=$((i-1))
	printf '[model #%s] (openMVS %s/%s) Converting data from colmap ' "$i" "$STEP_N" "$ALL_REST_STEPS" | tee -a "$WORKSPACE"/log
	START=$(date +%s)
	set +e
	InterfaceCOLMAP \
		--input-file "$WORKSPACE"/colmap/dense/$MODEL_NUMBER/ \
		--output-file "$WORKSPACE"/openmvs/scene.mvs \
		--image-folder "$IMAGE_DIR"  \
		>> "$WORKSPACE"/log 2>>"$WORKSPACE"/log
	RET=$?

	set -e
	END=$(date +%s)

	print_time "$((END-START))" | tee -a "$WORKSPACE"/log
	if ! [ "$RET" = "0" ]
	then
		echo Failed. Couldn\'t process this model | tee -a "$WORKSPACE"/log
		if ! [ "$(find "$WORKSPACE"/openmvs/ -mindepth 1)" = "" ]
		then
			rm -r "$WORKSPACE"/openmvs/* \
			     >> "$WORKSPACE"/log 2>>"$WORKSPACE"/log
		fi
		continue
	fi

	STEP_N=$((STEP_N+1))

	printf '[model #%s] (openMVS %s/%s) Reconstructing mesh ' "$i" "$STEP_N" "$ALL_REST_STEPS" | tee -a "$WORKSPACE"/log
	START=$(date +%s)
	set +e
	ReconstructMesh "$WORKSPACE"/openmvs/scene.mvs \
		--pointcloud-file "$WORKSPACE"/openmvs/scene.ply \
		>> "$WORKSPACE"/log 2>>"$WORKSPACE"/log
	RET=$?
	set -e

	END=$(date +%s)
	print_time "$((END-START))" | tee -a "$WORKSPACE"/log

	if ! [ "$RET" = "0" ]
	then
		echo Failed. Couldn\'t process this model | tee -a "$WORKSPACE"/log
		rm -r "$WORKSPACE"/openmvs/* \
		     >> "$WORKSPACE"/log 2>>"$WORKSPACE"/log
		continue
	fi

	STEP_N=$((STEP_N+1))

	#Skip refining if quality isn't set ot best_quality
	if [ "$QUALITY_SETTING" = "best_quality" ]
	then
		printf '[model #%s] (openMVS %s/%s) Refining mesh ' "$i" "$STEP_N" "$ALL_REST_STEPS" | tee -a "$WORKSPACE"/log
		START=$(date +%s)
		SUCESS=1
		#TODO: check if we can change scene_dense_mesh_refine.mvs to scene_dense_mesh_refine.ply
		if ! RefineMesh scene.mvs \
			--resolution-level 0 \
			--mesh-file "$WORKSPACE"/openmvs/scene_mesh.ply \
			--output-file "$WORKSPACE"/openmvs/scene_dense_mesh_refine.mvs \
			>> "$WORKSPACE"/log 2>>"$WORKSPACE"/log
		then
			SUCESS=0
		fi

		END=$(date +%s)
		print_time "$((END-START))" | tee -a "$WORKSPACE"/log

		if [ "$SUCESS" = 1 ]
		then
			FULL_RES_RECONSTRUCTED_MODEL="$WORKSPACE"/openmvs/scene_dense_mesh_refine.ply
		else
			echo Refining mesh failed! Using output from reconstruction | tee -a "$WORKSPACE"/log
			FULL_RES_RECONSTRUCTED_MODEL="$WORKSPACE"/openmvs/scene_mesh.ply
		fi

		STEP_N=$((STEP_N+1))

	elif [ "$QUALITY_SETTING" = "litest_resources" ]
	then
		FULL_RES_RECONSTRUCTED_MODEL="$WORKSPACE"/openmvs/scene_mesh.ply
	else
		echo INTERNAL_ERROR | tee -a "$WORKSPACE"/log
		exit 1
	fi

	mkdir "$WORKSPACE"/openmvs/out

	printf '[model #%s] (openMVS %s/%s) Texturing mesh ' "$i" "$STEP_N" "$ALL_REST_STEPS" | tee -a "$WORKSPACE"/log
	START=$(date +%s)

	if [ "$QUALITY_SETTING" = "best_quality" ]
	then
		TEXTURE_MESH_ARGS="--resolution-level 0 --patch-packing-heuristic 0"
	elif [ "$QUALITY_SETTING" = "litest_resources" ]
	then
		TEXTURE_MESH_ARGS="--resolution-level 6 --min-resolution 640 --patch-packing-heuristic 100"
	else
		echo INTERNAL_ERROR | tee -a "$WORKSPACE"/log
		exit 1
	fi
	set +e
	#shellcheck disable=SC2086
	TextureMesh scene.mvs \
		--mesh-file "$FULL_RES_RECONSTRUCTED_MODEL" \
		--output-file "$WORKSPACE"/openmvs/out/model-"$SEED".ply \
		--export-type ply \
		--archive-type 2 \
		--virtual-face-images 3 \
		--sharpness-weight 0 \
		$TEXTURE_MESH_ARGS \
		>> "$WORKSPACE"/log 2>>"$WORKSPACE"/log
	RET=$?
	set -e

	END=$(date +%s)
	print_time "$((END-START))" | tee -a "$WORKSPACE"/log

	if ! [ "$RET" = "0" ]
	then
		echo Failed. Couldn\'t process this model | tee -a "$WORKSPACE"/log
		rm -r "$WORKSPACE"/openmvs/* \
		     >> "$WORKSPACE"/log 2>>"$WORKSPACE"/log
		continue
	fi

	STEP_N=$((STEP_N+1))

	printf '[model #%s] (%s/%s) Moving final model to output directory ' "$i" "$STEP_N" "$ALL_REST_STEPS" | tee -a "$WORKSPACE"/log
	START=$(date +%s)
	set +e
	mv "$WORKSPACE"/openmvs/out/ "${OUTPUT_DIR}/$MODEL_NUMBER" \
		>> "$WORKSPACE"/log 2>>"$WORKSPACE"/log
	RET1=$?
	printf 'script_version=%s\nseed=%s\ncmd_line=%s\n' "$VERSION" "$SEED" "$CMD_LINE" > "${OUTPUT_DIR}/$MODEL_NUMBER"/script-version.txt
	RET2=$?
	set -e

	END=$(date +%s)
	print_time "$((END-START))" | tee -a "$WORKSPACE"/log

	if ! [ "$RET1" = "0" ] || ! [ "$RET2" = "0" ]
	then
		echo Failed to copy the model to the output directory. | tee -a "$WORKSPACE"/log
		rm -r "$WORKSPACE"/openmvs/* \
		     >> "$WORKSPACE"/log 2>>"$WORKSPACE"/log
		continue
	fi

	STEP_N=$((STEP_N+1))

	printf '[model #%s] (ACVD %s/%s) Creating low polygon mesh ' "$i" "$STEP_N" "$ALL_REST_STEPS" | tee -a "$WORKSPACE"/log
	START=$(date +%s)
	set +e
	ACVDQ "$FULL_RES_RECONSTRUCTED_MODEL" 1500 1.5 \
		-m 1 \
		>> "$WORKSPACE"/log 2>>"$WORKSPACE"/log
	RET=$?
	set -e

	END=$(date +%s)
	print_time "$((END-START))" | tee -a "$WORKSPACE"/log

	#TODO make this a function
	if ! [ "$RET" = "0" ]
	then
		echo Failed. Couldn\'t process this model | tee -a "$WORKSPACE"/log
		rm -r "$WORKSPACE"/openmvs/* \
		     >> "$WORKSPACE"/log 2>>"$WORKSPACE"/log
		continue
	fi

	STEP_N=$((STEP_N+1))

	printf '[model #%s] (openMVS %s/%s) Texturing low-polygon mesh ' "$i" "$STEP_N" "$ALL_REST_STEPS" | tee -a "$WORKSPACE"/log
	START=$(date +%s)
	mkdir out-low-poly

	set +e
	#shellcheck disable=SC2086
	TextureMesh scene.mvs \
		--mesh-file simplification.ply \
		--output-file out-low-poly/model-"$SEED"-low-poly.ply \
		--export-type ply \
		--archive-type 2 \
		--virtual-face-images 3 \
		--sharpness-weight 0 \
		$TEXTURE_MESH_ARGS \
		>> "$WORKSPACE"/log 2>>"$WORKSPACE"/log
	RET1=$?
	mv out-low-poly/* "${OUTPUT_DIR}/$MODEL_NUMBER"/. \
		>> "$WORKSPACE"/log 2>>"$WORKSPACE"/log
	RET2=$?
	set -e

	if ! [ "$RET1" = "0" ] || ! [ "$RET2" = "0" ]
	then
		echo Failed to copy the model to the output directory. | tee -a "$WORKSPACE"/log
		rm -r "$WORKSPACE"/openmvs/* \
		     >> "$WORKSPACE"/log 2>>"$WORKSPACE"/log
		continue
	fi

	END=$(date +%s)
	print_time "$((END-START))" | tee -a "$WORKSPACE"/log

	STEP_N=$((STEP_N+1))

	printf '[model #%s] (%s/%s) Cleaning data ' "$i" "$STEP_N" "$ALL_REST_STEPS" | tee -a "$WORKSPACE"/log
	rm -r "$WORKSPACE"/openmvs/* \
		>> "$WORKSPACE"/log 2>>"$WORKSPACE"/log
	echo | tee -a "$WORKSPACE"/log
done

if [ "$CLEAN_WORK_DIR" = 1 ]
then
	echo Cleaning up colmap data | tee -a "$WORKSPACE"/log
	rm -r "$WORKSPACE"/colmap/ "$WORKSPACE"/openmvs/
	if [ "$WORKSPACE_SET" = 0 ]
	then
		rm -r "$WORKSPACE"
	fi
fi
