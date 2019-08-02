#!/bin/bash

# ------------ Usage ------------------------------------------------------------------->
# cd /shared/uher/FORBOW/NIHPD_analysis/
# ./_1_scripts/DWI_0_generate_vectors.sh `/bin/ls -d [0,1]??_*`
# ---------------------------------------------------------------------------------------


Usage() {
	echo -e "\nUsage: `basename $0` <ssid>\n" 
	echo
	exit 1
}

SCRIPT=$(python -c "import os; print os.path.abspath('$0')")
SCRIPTSDIR=$(dirname $SCRIPT)
PROJECT_DIR=$(dirname $SCRIPTSDIR)
source "${SCRIPTSDIR}/FSv6_SetupHCPPipeline.sh"  #setup Freesurfer, FSL, and Pipeline defaults...
echo "PROJECT_DIR: $PROJECT_DIR"
echo "SCRIPT: $SCRIPT"
echo "SCRIPTSDIR: $SCRIPTSDIR"

FORCE_OVERWRITE="no"
if [ "$1" == "-f" ] ; then
	FORCE_OVERWRITE="yes"
	shift ;
	echo " * enabling FORCE_OVERWRITE"
fi

[ "$#" -lt 1 ] && Usage

T_DIR="${PROJECT_DIR}/_0_software/HCPpipelines_FSv6/global/templates"
T_MNI_BRAIN="${T_DIR}/MNI152_T1_1mm_brain.nii.gz"
T_MNI="${T_DIR}/MNI152_T1_1mm.nii.gz"
T_NIHPD_BRAIN="${T_DIR}/nihpd_asym_04.5-18.5_1mm_t1w_brain.nii.gz"
T_NIHPD="${T_DIR}/nihpd_asym_04.5-18.5_1mm_t1w.nii.gz"
T_MNI2NIHPD_WARP="${T_DIR}/mni_2nihpd_nonlin_warp.nii.gz"

VERBOSE="no"

DSTR=$(date +%Y%m%d)
RFILE="$PROJECT_DIR/_2_results/${DSTR}_DTI_vector_results.csv"
rm -f $RFILE


SUBJECTS="$@"

let iSubj=0
for Subj in $SUBJECTS ; do 
	
	S=$(basename $Subj)
	SDIR="$PROJECT_DIR/$S"
	
	if [ ! -d "$SDIR/T1w" ]; then
		echo -e "\n*** ERROR: cannot find data folder=[$SDIR/T1w]\n"
		continue
	fi
	if [ ! -d "$SDIR/DWI" ]; then
		echo -e "\n*** ERROR: cannot find data folder=[$SDIR/DWI]\n"
		continue
	fi
	DDIR="$SDIR/DWI"
	cd $DDIR/
	ecDIR="$DDIR/2_eddy"
	regDIR="$DDIR/4_reg"
	vecDIR="$DDIR/5_vectors"
	
	##  ensure dtifit has been run to generate vectors in DWI-space.
	if [ "$(imtest $vecDIR/dti_RD.nii.gz)" -eq 0 ]; then
		echo "*** ERROR: could not find file = $vecDIR/dti_RD.nii.gz"
		continue
	fi
	## ensure registration to T1w-acpc has been run
	if [ "$(imtest $regDIR/t1_brain_2dwi.nii.gz)" -eq 0 ]; then
		echo "*** ERROR: could not find file = $regDIR/t1_brain_2dwi.nii.gz"
		continue
	fi
	
	roiDIR="$DDIR/6_AtlasROIs"
	if [ "$FORCE_OVERWRITE" == "yes" ]; then
		echo " * FORCE_OVERWRITE enabled, removing ${roiDIR}/"
		rm -rf "${roiDIR}/"
	fi
	mkdir -p $roiDIR/ && cd $roiDIR/
	
	### 1) ensure necessary matrices, warps, etc, exist here 
	
	### 1) register JHU-WM20 to Subject-DWI-space, combining MNI->T1wACPC_nonlinear_warp.nii and T1wACPC->DWI.mat
	if [ ! -f "nodif.nii.gz" ]; then
		cp -pv $regDIR/nodif.nii.gz nodif.nii.gz
	fi
	if [ ! -f "t1.nii.gz" ]; then
		cp -pv $regDIR/t1.nii.gz t1.nii.gz
		cp -pv $regDIR/t1_brain.nii.gz t1_brain.nii.gz
		cp -pv $regDIR/t1_brain_2dwi.nii.gz t1_brain_2dwi.nii.gz
	fi
	if [ ! -f "t1_2dwi.mat" ]; then
		cp -pv $regDIR/dwi_2acpc_inv.mat t1_2dwi.mat
	fi
	if [ ! -f "nihpd_2t1_nonlin_warp.nii.gz" ]; then
		cp -pv $SDIR/MNINonLinear/xfms/standard2acpc_dc.nii.gz nihpd_2t1_nonlin_warp.nii.gz
	fi
	
	if [ "$(imtest mni_2t1_nonlin_warp.nii.gz)" -eq 0 ]; then
		echo " ++ combining warps (MNI -> NIHPD -> T1w) with convertwarp" 
		convertwarp -r t1.nii.gz -o mni_2t1_nonlin_warp --warp1=${T_MNI2NIHPD_WARP} --warp2=nihpd_2t1_nonlin_warp.nii.gz
	fi
	if [ "$(imtest mni_t1_brain_2dwi.nii.gz)" -eq 0 ]; then
		echo " ++ applywarp to register ${T_MNI_BRAIN} to DWI"
		applywarp -i ${T_MNI_BRAIN} -r nodif.nii -w mni_2t1_nonlin_warp --postmat=t1_2dwi.mat -o mni_t1_brain_2dwi
	fi
	
	### generate DWI_QC_motion report
	subjQCcsv="${S}_DWI_QC_motion_report.csv"
	if [ "$FORCE_OVERWRITE" == "yes" ]; then
		rm -f ${subjQCcsv} >/dev/null
	fi
	if [ ! -r "$subjQCcsv" ]; then
		Hdr="SSID,DWI_QC_motion_abs_rms_mean,DWI_QC_motion_rel_rms_mean"
		V=$($SCRIPTSDIR/eddy_summarize_motion_rms.py $ecDIR/data_ec.eddy_restricted_movement_rms)
		Data="$S,$V"
		if [ "$iSubj" -eq 0 ]; then
			if [ "$VERBOSE" == "yes" ]; then echo "$Hdr" ; fi
			echo "$Hdr" >$RFILE
		fi
		echo "$Hdr" >$subjQCcsv 
		echo "$Data" >>$subjQCcsv
		echo "$Data" >>$RFILE
		if [ "$VERBOSE" == "yes" ]; then echo "$Data"; fi
	fi
	
	### generate WM20_ROI_Vector stats report
	subjWM20="${S}_FSL_WM20_vector_stats.csv"
	if [ "$FORCE_OVERWRITE" == "yes" ]; then
		rm -f ${subjWM20} >/dev/null
		#imrm JHU_*_2dwi.nii.gz 
	fi
	if [ ! -r "$subjWM20" ]; then
		Hdr="SSID"
		Data="$S"
		mkdir -p FSL-JHU-WM20-ROIs/
		for mask in $(imglob $PROJECT_DIR/_3_docs/FSL_JHU_WM20/JHU_WM20_Masks_Thr0/*_mask.nii.gz); do
			f=$(basename $mask) 
			bn=$(basename $f _mask)
			sm="FSL-JHU-WM20-ROIs/${bn}_2dwi.nii.gz"
			if [ "$(imtest $sm)" -eq 0 ]; then
				if [ "$VERBOSE" == "yes" ]; then echo " ++ registering JHU-WM-20-ROI = $f"; fi
				applywarp -i $mask -r nodif.nii -w mni_2t1_nonlin_warp.nii.gz --postmat=t1_2dwi.mat -o $sm --interp=nn
			fi
			vol=$(fslstats $sm -V | awk '{print $2}')
			Hdr="${Hdr},${bn}_vol"
			Data="${Data},${vol}"
			for vec in FA MD AD RD ; do
				vFile="$vecDIR/dti_${vec}"
				R=$(fslstats $vFile -k $sm -m -s)
				if [ "$VERBOSE" == "yes" ]; then echo "-- $vec results for $bn:  $R"; fi
				Hdr="${Hdr},${bn}_${vec}_mean,${bn}_${vec}_std"
				Data="${Data},$(echo $R | awk '{print $1","$2}')"
			done
		done
		if [ "$iSubj" -eq 0 ]; then
			if [ "$VERBOSE" == "yes" ]; then echo "$Hdr" ; fi
			echo "$Hdr" >$RFILE
		fi
		echo "$Hdr" >$subjWM20 
		echo "$Data" >>$subjWM20
		echo "$Data" >>$RFILE
		if [ "$VERBOSE" == "yes" ]; then echo "$Data"; fi
	fi
	
	
	subjWM48="${S}_FSL_WM48_vector_stats.csv"
	if [ "$FORCE_OVERWRITE" == "yes" ]; then 
		rm -f ${subjWM48} >/dev/null
	fi
	if [ ! -r "$subjWM48" ]; then
		wmLabels="$PROJECT_DIR/_3_docs/FSL_JHU_WM48/JHU-labels.csv"
		wmMap=$(imglob $PROJECT_DIR/_3_docs/FSL_JHU_WM48/JHU-ICBM-labels-1mm.nii.gz)
		if [ "$(imtest $wmMap)" -eq 0 ]; then
			echo "*** ERROR: cannot find file = $wmMap"
			let iSubj=iSubj+1
			continue
		fi
		dwiWM="$(basename $wmMap)_2dwi"
		echo " ++ registering $wmLabels --> dwi"
		applywarp -i $wmMap -r nodif.nii -w mni_2t1_nonlin_warp.nii.gz --postmat=t1_2dwi.mat -o $dwiWM --interp=nn
		
		#dump out and mask each ROI
		mkdir -p JHU-WM48-ROIs/
		Hdr="SSID"
		Data="$S"
		for r in $(cat -v $wmLabels); do
			roiIndex=$(echo $r | awk -F, '{print $1}')
			roiName=$(echo $r | awk -F, '{print $2}')
			roiNum=$(printf '%03d' $roiIndex)
			roiFile="JHU-WM48-ROIs/roi_${roiNum}.nii.gz"
			fslmaths $dwiWM -thr $roiIndex -uthr $roiIndex -bin $roiFile
			vol=$(fslstats $roiFile -V | awk '{print $2}')
			if [ "$VERBOSE" == "yes" ]; then echo " ++ $roiIndex=($roiName), vol=$vol"; fi
			Hdr="${Hdr},${roiName}_vol"
			Data="${Data},${vol}"
			for vec in FA MD AD RD ; do
				vFile="$vecDIR/dti_${vec}"
				R=$(fslstats $vFile -k $roiFile -m -s)
				if [ "$VERBOSE" == "yes" ]; then echo "-- $vec results for $bn: $R"; fi
				Hdr="${Hdr},${roiName}_${vec}_mean,${roiName}_${vec}_std"
				Data="${Data},$(echo $R | awk '{print $1","$2}')"
			done
		done
		if [ "$iSubj" -eq 0 ]; then
			if [ "$VERBOSE" == "yes" ]; then echo "$Hdr" ; fi
			echo "$Hdr" >$RFILE
		fi
		echo "$Hdr" >$subjWM48
		echo "$Data" >>$subjWM48
		echo "$Data" >>$RFILE
		if [ "$VERBOSE" == "yes" ]; then echo "$Data"; fi
	fi
	
	
	subjWMparc="${S}_FS_wmparc_vector_stats.csv"
	if [ "$FORCE_OVERWRITE" == "yes" ]; then  
		rm -f ${subjWMparc} >/dev/null 
	fi
	if [ ! -r "$subjWMparc" ]; then
		wmLabels="$PROJECT_DIR/_3_docs/FS_WMPARC/wmparc_labels.csv"
		wmparc=$(imglob $SDIR/T1w/wmparc.nii.gz)
		if [ ! -r "$wmLabels" ]; then
			echo "*** ERROR: cannot find file = $wmLabels"
		elif [ "$(imtest $wmparc)" -eq 0 ]; then
			echo "*** ERROR: cannot find file = $wmparc"
		else
			dwiWM=$(basename $wmparc)_2dwi
			echo " ++ registering wmparc file from T1w --> DWI"
			applywarp -i $wmparc -r nodif --postmat=t1_2dwi.mat -o $dwiWM --interp=nn
			#dump out and mask each ROI
			mkdir -p FS-WMPARC-ROIs/
			Hdr="SSID"
			Data="$S"
			for r in $(cat $wmLabels); do
				roiIndex=$(echo $r | awk -F, '{print $1}')
				roiName=$(echo $r | awk -F, '{print $2}')
				roiNum=$(printf '%03d' $roiIndex)
				roiFile="FS-WMPARC-ROIs/roi_${roiNum}.nii.gz"
				fslmaths $dwiWM -thr $roiIndex -uthr $roiIndex -bin $roiFile
				vol=$(fslstats $roiFile -V | awk '{print $2}')
				if [ "$VERBOSE" == "yes" ]; then echo " ++ $roiIndex=($roiName), vol=$vol"; fi
				Hdr="${Hdr},${roiName}_vol"
				Data="${Data},${vol}"
				for vec in FA MD AD RD ; do
					vFile="$vecDIR/dti_$vec"
					R=$(fslstats $vFile -k $roiFile -m -s)
					if [ "$VERBOSE" == "yes" ]; then echo "-- $vec results for ${bn}: $R"; fi
					Hdr="${Hdr},${roiName}_${vec}_mean,${roiName}_${vec}_std"
					Data="${Data},$(echo $R | awk '{print $1","$2}')"
				done
			done
			if [ "$iSubj" -eq 0 ]; then
				if [ "$VERBOSE" == "yes" ]; then echo "$Hdr" ; fi
				echo "$Hdr" >$RFILE
			fi
			echo "$Hdr" >$subjWMparc
			echo "$Data" >>$subjWMparc
			echo "$Data" >>$RFILE
			if [ "$VERBOSE" == "yes" ]; then echo "$Data"; fi
		fi
	fi
	
	
	subjHemiWM="${S}_FS_WM_Hemisphere_stats.csv"
	if [ "$FORCE_OVERWRITE" == "yes" ]; then 
		rm -f ${subjHemiWM} >/dev/null
	fi
	if [ ! -r "$subjHemiWM" ]; then
		if [ "$(imtest ${SDIR}/T1w/aparc+aseg.nii.gz)" -eq 0 ]; then
			echo "*** ERROR: cannot find ${SDIR}/T1w/aparc+aseg.nii.gz"
		else
			fslmaths ${SDIR}/T1w/aparc+aseg.nii.gz -thr 2 -uthr 2 -bin ${SDIR}/T1w/aparc+aseg_wm_L
			fslmaths ${SDIR}/T1w/aparc+aseg.nii.gz -thr 41 -uthr 41 -bin ${SDIR}/T1w/aparc+aseg_wm_R
			Hdr="SSID"
			Data="$S"
			for H in wm_L wm_R ; do
				roiName="FS_aparc+aseg_${H}"
				roiFile="${roiName}_2dwi"
				echo " ++ registering ${roiName} from T1w --> DWI"
				applywarp -i "${SDIR}/T1w/aparc+aseg_${H}" -r nodif --postmat=t1_2dwi.mat -o $roiFile --interp=nn
				vol=$(fslstats $roiFile -V | awk '{print $2}')
				Hdr="${Hdr},${roiName}_vol"
				Data="${Data},${vol}"
				for vec in FA MD AD RD ; do
					vFile="$vecDIR/dti_$vec"
					R=$(fslstats $vFile -k $roiFile -m -s)
					if [ "$VERBOSE" == "yes" ]; then echo "-- $vec results for ${bn}: $R"; fi
					Hdr="${Hdr},${roiName}_${vec}_mean,${roiName}_${vec}_std"
					Data="${Data},$(echo $R | awk '{print $1","$2}')"
				done
			done
 			if [ "$iSubj" -eq 0 ]; then
				if [ "$VERBOSE" == "yes" ]; then echo "$Hdr" ; fi
				echo "$Hdr" >$RFILE
			fi
			echo "$Hdr" >$subjHemiWM
			echo "$Data" >>$subjHemiWM
			echo "$Data" >>$RFILE
			if [ "$VERBOSE" == "yes" ]; then echo "$Data"; fi

		fi
	fi
	
	let iSubj=iSubj+1
done

exit 0

