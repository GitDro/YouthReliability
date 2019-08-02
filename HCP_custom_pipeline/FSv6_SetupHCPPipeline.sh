#!/bin/bash 


################ OpenMP Setup ####################################################
## (NEPTUNE): by default OMP_NUM_THREADS is set to NCORES (24). 
## We usually run up to 6 "Full HCP Pipelines" (Structural,DWI,RS,LGI) at once in parallel, 
## but staggered by 300-600 seconds to balance multi-core sections to run along with single-core sections.
## Assuming we set njobs-at-once=4, then thus 24/4=6; USE_NCORES_DEFAULT=6
if [ "`uname -n`" == "neptune" ]; then
	export OMP_NUM_THREADS=6   ## (NEPTUNE) set OMP_NUM_THREADS=6 and start 4 jobs at once
elif [ "`uname -n`" == "jaylah" ]; then
	export OMP_NUM_THREADS=6   ## (JAYLAH) set OMP_NUMTHREADS=8 and start 6 jobs at once
else
	export OMP_NUM_THREADS=4	## probably a mac...
	echo
	echo "*** WARNING ***: you should be using LINUX for FORBOW HCP-Pipeline Analysis...exiting now"
	echo
	#exit 1
fi

NCORES=$(parallel --number-of-cores | awk '{print $1}')
echo " * HOSTNAME=$HOSTNAME: found NUM_TOTAL_CORES=$NCORES; NREAL_CORES=$(echo "0.5*$NCORES" | bc), exporting OMP_NUM_THREADS=${OMP_NUM_THREADS}, `date`"


# Set up FSL (if not already done so in the running environment)
# Uncomment the following 2 lines (remove the leading #) and correct the FSLDIR setting for your setup
export FSLDIR=/usr/local/fsl-6.0.0
export PATH="${FSLDIR}/bin:${PATH}"
source ${FSLDIR}/etc/fslconf/fsl.sh

# Let FreeSurfer know what version of FSL to use
# FreeSurfer uses FSL_DIR instead of FSLDIR to determine the FSL version
export FSL_DIR="${FSLDIR}"

# Set up FreeSurfer (if not already done so in the running environment)
# Uncomment the following 2 lines (remove the leading #) and correct the FREESURFER_HOME setting for your setup
export FREESURFER_HOME=/usr/local/freesurfer/6.0
source ${FREESURFER_HOME}/SetUpFreeSurfer.sh > /dev/null 2>&1


export PROJECT_DIR=/shared/uher/FORBOW/NIHPD_analysis


# Set up specific environment variables for the HCP Pipeline
export HCPPIPEDIR=${PROJECT_DIR}/_0_software/HCPpipelines_FSv6
export CARET7DIR=${PROJECT_DIR}/_0_software/workbench/bin_linux64
export MSMBINDIR=${PROJECT_DIR}/_0_software/MSM_HOCR_v1
export MSMCONFIGDIR=${HCPPIPEDIR}/MSMConfig
export MATLAB_COMPILER_RUNTIME=/usr/local/MATLAB/MATLAB_Runtime/v91
export FSL_FIXDIR=${PROJECT_DIR}/_0_software/fix
export HCPPIPEDIR_Templates=${HCPPIPEDIR}/global/templates
export HCPPIPEDIR_Bin=${HCPPIPEDIR}/global/binaries
export HCPPIPEDIR_Config=${HCPPIPEDIR}/global/config
export HCPPIPEDIR_PreFS=${HCPPIPEDIR}/PreFreeSurfer/scripts
export HCPPIPEDIR_FS=${HCPPIPEDIR}/FreeSurfer/scripts
export HCPPIPEDIR_PostFS=${HCPPIPEDIR}/PostFreeSurfer/scripts
export HCPPIPEDIR_fMRISurf=${HCPPIPEDIR}/fMRISurface/scripts
export HCPPIPEDIR_fMRIVol=${HCPPIPEDIR}/fMRIVolume/scripts
export HCPPIPEDIR_tfMRI=${HCPPIPEDIR}/tfMRI/scripts
export HCPPIPEDIR_dMRI=${HCPPIPEDIR}/DiffusionPreprocessing/scripts
export HCPPIPEDIR_dMRITract=${HCPPIPEDIR}/DiffusionTractography/scripts
export HCPPIPEDIR_Global=${HCPPIPEDIR}/global/scripts
export HCPPIPEDIR_tfMRIAnalysis=${HCPPIPEDIR}/TaskfMRIAnalysis/scripts
export PATH="${HCPPIPEDIR}/FreeSurferCustomizations:${PATH}"

#try to reduce strangeness from locale and other environment settings
export LC_ALL=C
export LANGUAGE=C
#POSIXLY_CORRECT currently gets set by many versions of fsl_sub, unfortunately, but at least don't pass it in if the user has it set in their usual environment
unset POSIXLY_CORRECT

#### 2016/07/07-CAH: moved from DiffPreprocPipeline_PostEddy.sh ###############
#### Had been set to 1, but would only return 8 volumes, unless we duplicated 8volumes to create matching 33vols.
# Hard-Coded variables for the pipeline
export PostEddyDataCombineFlag=0  
# If JAC resampling has been used in eddy, decide what to do with the output file
# 2 for including in the output all volumes uncombined (i.e. output file of eddy)
# 1 for including in the output and combine only volumes where both LR/RL
#   (or AP/PA) pairs have been acquired
# 0 As 1, but also include uncombined single volumes



create_1x3_overlay(){
	echo " ++ creating 1x3 overlay from ${1} -> ${2} using lut=${3}"
	slicer ${1} -l ${3} -s 2 -a ${2}
}
create_1x3_RedEdge_overlay(){
	echo " ++ creating 1x3 red-edged overlay from ${1} on ${2} -> ${3}"
	slicer ${1} ${2} -s 2 -a ${3}
}
create_9x1_slicer(){
	echo " ++ creating 9x1 SingleImage from $1 -> $2"
	outImg="$2"
	if [ "${outImg:${#outImg}-4:4}" != ".png" ]; then outImg="${outImg}.png"; fi
	tmp=$(${FSLDIR}/bin/tmpnam)
	slicer ${1} -s 2 -u -x 0.4 ${tmp}_x1.png -x 0.5 ${tmp}_x2.png -x 0.6 ${tmp}_x3.png -y 0.4 ${tmp}_y1.png -y 0.5 ${tmp}_y2.png -y 0.6 ${tmp}_y3.png -z 0.4 ${tmp}_z1.png -z 0.5 ${tmp}_z2.png -z 0.6 ${tmp}_z3.png 
	opts="${tmp}_x1.png + ${tmp}_x2.png + ${tmp}_x3.png + ${tmp}_y1.png + ${tmp}_y2.png + ${tmp}_y3.png + ${tmp}_z1.png + ${tmp}_z2.png + ${tmp}_z3.png"
	pngappend ${opts} ${outImg}
	rm -f ${tmp}*.png
}
create_9x1_midbrain_overlay(){
	echo " ++ creating 9x1 overlay from $1 -> $2 using lut=$3"
	tmp=$(${FSLDIR}/bin/tmpnam)
	slicer ${1} -l ${3} -s 2 -u -x 0.4 ${tmp}_x1.png -x 0.5 ${tmp}_x2.png -x 0.6 ${tmp}_x3.png -y 0.45 ${tmp}_y1.png -y 0.5 ${tmp}_y2.png -y 0.55 ${tmp}_y3.png -z 0.35 ${tmp}_z1.png -z 0.4 ${tmp}_z2.png -z 0.45 ${tmp}_z3.png 
	opts="${tmp}_x1.png + ${tmp}_x2.png + ${tmp}_x3.png + ${tmp}_y1.png + ${tmp}_y2.png + ${tmp}_y3.png + ${tmp}_z1.png + ${tmp}_z2.png + ${tmp}_z3.png"
	pngappend ${opts} ${2}
	rm -f ${tmp}*.png
}
create_9x1_midbrain_RedEdge_overlay(){
	echo " ++ creating 9x1 red-edged overlay from $1 on $2 -> $3"
	tmp=$(${FSLDIR}/bin/tmpnam)
	slicer ${1} ${2} -s 2 -u -x 0.4 ${tmp}_x1.png -x 0.5 ${tmp}_x2.png -x 0.6 ${tmp}_x3.png -y 0.45 ${tmp}_y1.png -y 0.5 ${tmp}_y2.png -y 0.55 ${tmp}_y3.png -z 0.35 ${tmp}_z1.png -z 0.4 ${tmp}_z2.png -z 0.45 ${tmp}_z3.png 
	opts="${tmp}_x1.png + ${tmp}_x2.png + ${tmp}_x3.png + ${tmp}_y1.png + ${tmp}_y2.png + ${tmp}_y3.png + ${tmp}_z1.png + ${tmp}_z2.png + ${tmp}_z3.png"
	pngappend ${opts} ${3}
	rm -f ${tmp}*.png
}
create_9x1_overlay(){
	echo " ++ creating 9x1 overlay from $1 -> $2 using lut=$3"
	tmp=$(${FSLDIR}/bin/tmpnam)
	slicer ${1} -l ${3} -s 2 -u -x 0.4 ${tmp}_x1.png -x 0.5 ${tmp}_x2.png -x 0.6 ${tmp}_x3.png -y 0.4 ${tmp}_y1.png -y 0.5 ${tmp}_y2.png -y 0.6 ${tmp}_y3.png -z 0.4 ${tmp}_z1.png -z 0.5 ${tmp}_z2.png -z 0.6 ${tmp}_z3.png 
	opts="${tmp}_x1.png + ${tmp}_x2.png + ${tmp}_x3.png + ${tmp}_y1.png + ${tmp}_y2.png + ${tmp}_y3.png + ${tmp}_z1.png + ${tmp}_z2.png + ${tmp}_z3.png"
	pngappend ${opts} ${2}
	rm -f ${tmp}*.png
}
create_9x1_RedEdge_overlay(){
	echo " ++ creating 9x1 red-edged overlay of $1 on $2 -> $3"
	tmp=$(${FSLDIR}/bin/tmpnam)
	slicer ${1} ${2} -s 2 -u -x 0.4 ${tmp}_x1.png -x 0.5 ${tmp}_x2.png -x 0.6 ${tmp}_x3.png -y 0.4 ${tmp}_y1.png -y 0.5 ${tmp}_y2.png -y 0.6 ${tmp}_y3.png -z 0.4 ${tmp}_z1.png -z 0.5 ${tmp}_z2.png -z 0.6 ${tmp}_z3.png 
	opts="${tmp}_x1.png + ${tmp}_x2.png + ${tmp}_x3.png + ${tmp}_y1.png + ${tmp}_y2.png + ${tmp}_y3.png + ${tmp}_z1.png + ${tmp}_z2.png + ${tmp}_z3.png"
	pngappend ${opts} ${3}
	rm -f ${tmp}*.png
}
create_12x1_overlay(){
	echo " ++ creating 12x1 overlay from $1 -> $2 using lut=$3"
	tmp=$(${FSLDIR}/bin/tmpnam)
	slicer ${1} -l ${3} -s 2 -u -z -30 ${tmp}_z01.png -z -40 ${tmp}_z02.png -z -50 ${tmp}_z03.png -z -60 ${tmp}_z04.png -z -70 ${tmp}_z05.png -z -80 ${tmp}_z06.png -z -90 ${tmp}_z07.png -z -100 ${tmp}_z08.png -z -110 ${tmp}_z09.png -z -120 ${tmp}_z10.png -z -130 ${tmp}_z11.png -z -140 ${tmp}_z12.png 
	opts="${tmp}_z01.png + ${tmp}_z02.png + ${tmp}_z03.png + ${tmp}_z04.png + ${tmp}_z05.png + ${tmp}_z06.png + ${tmp}_z07.png + ${tmp}_z08.png + ${tmp}_z09.png + ${tmp}_z10.png + ${tmp}_z11.png + ${tmp}_z12.png"
	pngappend ${opts} ${2}
	rm -f ${tmp}*.png
}
create_12x1_RedEdge_overlay(){
	echo " ++ creating 12x1 red-edged overlay from $1 on $2 -> $3"
	tmp=$(${FSLDIR}/bin/tmpnam)
	slicer ${1} ${2} -s 2 -u -z -30 ${tmp}_z01.png -z -40 ${tmp}_z02.png -z -50 ${tmp}_z03.png -z -60 ${tmp}_z04.png -z -70 ${tmp}_z05.png -z -80 ${tmp}_z06.png -z -90 ${tmp}_z07.png -z -100 ${tmp}_z08.png -z -110 ${tmp}_z09.png -z -120 ${tmp}_z10.png -z -130 ${tmp}_z11.png -z -140 ${tmp}_z12.png 
	opts="${tmp}_z01.png + ${tmp}_z02.png + ${tmp}_z03.png + ${tmp}_z04.png + ${tmp}_z05.png + ${tmp}_z06.png + ${tmp}_z07.png + ${tmp}_z08.png + ${tmp}_z09.png + ${tmp}_z10.png + ${tmp}_z11.png + ${tmp}_z12.png"
	pngappend ${opts} ${3}
	rm -f ${tmp}*.png
}
create_8x3_overlay(){
	echo " ++ creating 8x3 overlay from $1 -> $2 using lut=$3"
	tmp=$(${FSLDIR}/bin/tmpnam)
	for ((i=20; i<136; i+=5)); do 
		n=$(printf '%03d' $i); 
		slicer ${1} -l ${3} -s 2 -u -z -${i} ${tmp}${n}.png; 
	done
	pngappend ${tmp}020.png + ${tmp}025.png + ${tmp}030.png + ${tmp}035.png + ${tmp}040.png + ${tmp}045.png + ${tmp}050.png + ${tmp}055.png - ${tmp}060.png + ${tmp}065.png + ${tmp}070.png + ${tmp}075.png + ${tmp}080.png + ${tmp}085.png + ${tmp}090.png + ${tmp}095.png - ${tmp}100.png + ${tmp}105.png + ${tmp}110.png + ${tmp}115.png + ${tmp}120.png + ${tmp}125.png + ${tmp}130.png + ${tmp}135.png ${2}
	rm -f ${tmp}*.png
}
create_8x3_RedEdge_overlay(){
	echo " ++ creating 8x3 red-edged overlay from $1 on $2 -> $3"
	tmp=$(${FSLDIR}/bin/tmpnam)
	for ((i=20; i<136; i+=5)); do 
		n=$(printf '%03d' $i); 
		slicer ${1} ${2} -s 2 -u -z -${i} ${tmp}${n}.png; 
	done
	pngappend ${tmp}020.png + ${tmp}025.png + ${tmp}030.png + ${tmp}035.png + ${tmp}040.png + ${tmp}045.png + ${tmp}050.png + ${tmp}055.png - ${tmp}060.png + ${tmp}065.png + ${tmp}070.png + ${tmp}075.png + ${tmp}080.png + ${tmp}085.png + ${tmp}090.png + ${tmp}095.png - ${tmp}100.png + ${tmp}105.png + ${tmp}110.png + ${tmp}115.png + ${tmp}120.png + ${tmp}125.png + ${tmp}130.png + ${tmp}135.png ${3}
	rm -f ${tmp}*.png
}
