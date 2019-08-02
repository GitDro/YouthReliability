#!/bin/bash


Usage() {
	echo
	echo "Usage: `basename $0` <ssid>"
	echo
	echo "Example: `basename $0` 008"
	echo
	exit 1
}


SCRIPT=$(python -c "import os; print os.path.abspath('$0')")
SCRIPTSDIR=$(dirname $SCRIPT)
if [[ -z "${PROJECT_DIR}" ]]; then
	source "$SCRIPTSDIR/FSv6_SetupHCPPipeline.sh"
fi

FORCE_OVERWRITE="no"
if [ "$1" == "-f" ]; then
	FORCE_OVERWRITE="yes"
	shift ;
	echo "* enabling FORCE_OVERWRITE mode..."
fi
DEBUG_VERBOSE="yes"
FORCE_OVERWRITE_REG="yes"	
ENFORCE_EVEN_ZSLICES="yes"
DEFAULT_TOTAL_READOUT_TIME="0.073616"  ##copied from 001_C_FLAIR_DWI_dir30_AP.json (output from dcm2niix -b y...)
SQUAD_FILEPATH="${PROJECT_DIR}/_2_results/squad_subjlist_eddyqc.txt"

[ "$#" -lt 1 ] && Usage


let index=0
SUBJECTS="$@"
for Subj in $SUBJECTS ; do 
	
	S=$(basename $Subj)
	SDIR="$PROJECT_DIR/$S"
	if [ ! -d "$SDIR" ]; then
		echo "*** ERROR: cannot find subject directory = $SDIR"
		continue
	fi
	cd $SDIR/
	echo "--------------- Preprocessing DWI for $SDIR/, starting `date`"

	## setup data directories
	DDIR="$SDIR/DWI"
	if [ -d "$DDIR" ]; then
		if [ "$FORCE_OVERWRITE" == "yes" ]; then 
			rm -rf $DDIR/ >/dev/null
		fi
	fi
	if [ "$FORCE_OVERWRITE_REG" == "yes" ]; then
		rm -rf $DDIR/[4-6]_* $DDIR/QC/ >/dev/null
	fi
	mkdir -p $DDIR/ && cd $DDIR/
	
	rawDIR="$DDIR/0_rawdata"
	if [ "`imtest $rawDIR/dwi_peAP.nii.gz`" -eq 0 ]; then
		mkdir -p $rawDIR/
		if [ "`imtest $SDIR/unprocessed/Diffusion/${S}_DWI_dir30_AP.nii.gz`" -eq 0 ]; then
			echo -e "\n*** ERROR: cannot find raw dti file named: $SDIR/unprocessed/Diffusion/${S}_DWI_dir30_AP.nii\n"
			continue
		fi
		echo " ++ copying dwi_peAP.nii to $rawDIR/"
		cp -pv $SDIR/unprocessed/Diffusion/${S}_DWI_dir30_AP.nii.gz $rawDIR/dwi_peAP.nii.gz
		cp -pv $SDIR/unprocessed/Diffusion/${S}_DWI_dir30_AP.bval $rawDIR/dwi_peAP.bval
		cp -pv $SDIR/unprocessed/Diffusion/${S}_DWI_dir30_AP.bvec $rawDIR/dwi_peAP.bvec
		cp -pv $SDIR/unprocessed/Diffusion/${S}_DWI_dir30_AP.json  $rawDIR/dwi_peAP.json
	fi
	if [ "`imtest $rawDIR/dwi_pePA.nii.gz`" -eq 0 ]; then
		if [ "`imtest $SDIR/unprocessed/Diffusion/${S}_DWI_dir30_PA.nii.gz`" -eq 0 ]; then
			echo -e "\n*** ERROR: cannot find raw dti file named: $SDIR/unprocessed/Diffusion/${S}_DWI_dir30_PA.nii\n"
			continue
		fi
		echo " ++ copying dwi_pePA.nii to $rawDIR/"
		cp -pv $SDIR/unprocessed/Diffusion/${S}_DWI_dir30_PA.nii.gz $rawDIR/dwi_pePA.nii.gz
		cp -pv $SDIR/unprocessed/Diffusion/${S}_DWI_dir30_PA.bval $rawDIR/dwi_pePA.bval
		cp -pv $SDIR/unprocessed/Diffusion/${S}_DWI_dir30_PA.bvec $rawDIR/dwi_pePA.bvec
		cp -pv $SDIR/unprocessed/Diffusion/${S}_DWI_dir30_PA.json  $rawDIR/dwi_pePA.json
	fi
	
	
	## ------------- Topup --------------------------------------------------------------
	tuDIR="$DDIR/1_topup"
	## build 4D-volume file with *all* FWD/REV B0s, can use NVols each or means of motion-corrected NVols...
	if [ "`imtest $tuDIR/combined_B0s_orig.nii.gz`" -eq 0 ]; then
		mkdir -p $tuDIR/ && cd $tuDIR/
		for PE in peAP pePA ; do
			if [ "$DEBUG_VERBOSE" == "yes" ]; then
				echo "---- saving all [$PE] B0s..."; 
			fi
			mkdir -p $tuDIR/${PE}_B0s/
			cd $tuDIR/${PE}_B0s/
			data=$(imglob $rawDIR/dwi_${PE}.nii)
			bval="$rawDIR/dwi_${PE}.bval"
			B0Vols=$(python -c "x=[str(i) for i,v in enumerate(open('$bval','rU').read().split()) if v=='0']; print ','.join(x)")
			fslselectvols -i $data -o all_B0s --vols=${B0Vols}
			nBlocs=$(fslval all_B0s.nii dim4 | bc)
			if [ "$nBlocs" -lt 1 ]; then
				echo "ERROR: could not find a single b0 volume from BVALS file = $bval"
				exit 3
			else
				echo "found $nBlocs B0Locs=[${B0Vols}]"
			fi
			ROTIME=$(cat $rawDIR/dwi_${PE}.json | grep "TotalReadoutTime" | awk '{print $2}' | sed 's|,||g')
			if [ "`echo "$ROTIME<0.01" | bc`" -eq 1 ]; then
				echo " * Warning: unable to grep 'TotalReadoutTime' from dwi_${PE}.json; using default ROTIME=${DEFAULT_TOTAL_READOUT_TIME}"
				ROTIME="$DEFAULT_TOTAL_READOUT_TIME"
			fi
			YDIR="1"
			if [ "$PE" == "pePA" ]; then YDIR="-1"; fi
			rm -f acqparams.txt >/dev/null
			for ((i=0; $i<${nBlocs}; i++)) ; do
				echo "0 ${YDIR} 0 ${ROTIME}" >>acqparams.txt
			done
			mcflirt -in all_B0s -meanvol -spline_final -o all_B0s_mc
			fslmaths all_B0s_mc -thr 0 -Tmean all_B0s_mean
			#if [ "`imtest all_B0s_mean_2acpc.nii.gz`" -eq 0 ]; then
			#	t1DIR="$SDIR/T1w"
			#	### ********** THIS METHOD DOES NOT WORK *************
			#	### 1) registering means to T1w-ACPC generates an odd matrix dimension x,y,z = 91,109,91 @2mm isotropic.
			#	### 2) topup requires even dimensions, because the default --subsamp=2,2,2,2,2,1,1,1,1. This
			#	###    can be overriden by forcing --subsamp=1,1,1,1,1,1,1,1,1
			#	### 3) eddy requires both --imain and --mask to have same matrix dimensions...
			#	echo " ++ running flirt -bbr all_B0s_mean -> t1"
			#	flirt -in all_B0s_mean.nii -ref $t1DIR/${S}_t1.nii -dof 6 -finesearch 30 -cost normmi -omat all_B0s_2t1_prealign.mat -o all_B0s_2t1_prealign.nii.gz
			#	flirt -in all_B0s_mean.nii -ref $t1DIR/${S}_t1.nii -dof 6 -nosearch -cost bbr -wmseg $t1DIR/${S}_t1_wmseg.nii -init all_B0s_2t1_prealign.mat -omat all_B0s_2t1.mat -o all_B0s_2t1.nii.gz -schedule ${FSLDIR}/etc/flirtsch/bbr.sch
			#	flirt -in all_B0s_mean -ref $t1DIR/${S}_t1.nii -init all_B0s_2t1.mat -applyisoxfm 2.0 -interp spline -o all_B0s_mean_2acpc
			#	fslmaths all_B0s_mean_2acpc.nii -thr 0 all_B0s_mean_2acpc.nii
			#fi
		done ##for PE in peAP pePA ...
		cd $tuDIR/
		echo "--- creating file = combined_B0s.nii from first ${TOPUP_USE_NVOLS_EACH_PE} each peAP pePA mean B0s..."
		fslmerge -t combined_B0s_orig.nii peAP_B0s/all_B0s_mean.nii pePA_B0s/all_B0s_mean.nii
		rm -f acqparams.txt >/dev/null
		cat -v ./peAP_B0s/acqparams.txt | head -n 1 >>acqparams.txt
		cat -v ./pePA_B0s/acqparams.txt | head -n 1 >>acqparams.txt
		cat acqparams.txt
	fi
	
	cd $tuDIR/
	nslices=$(fslval combined_B0s_orig.nii dim3)
	EXTRA_Z_SLICE_ADDED=$(($nslices%2))
	if [ "`imtest $tuDIR/combined_B0s.nii.gz`" -eq 0 ]; then
		if [ "$ENFORCE_EVEN_ZSLICES" == "yes" -a "$EXTRA_Z_SLICE_ADDED" -eq 1 ]; then
			echo " ++ fixing odd Z-FOV volume dimensions before TOPUP, taking 1st slice from bottom, zeroing, and adding to top of combined_B0s.nii"
			fslroi combined_B0s_orig.nii combined_B0s_orig_slice0.nii 0 -1 0 -1 0 1
			fslmaths combined_B0s_orig_slice0.nii -mul 0 combined_B0s_orig_slice0.nii
			fslmerge -z combined_B0s.nii combined_B0s_orig.nii combined_B0s_orig_slice0.nii
			echo "-- padding bottom of actual 30-dir peAP dataset by adding a zero-ed slice to top of data.nii"
			fslroi ../0_rawdata/dwi_peAP.nii data_slice0.nii 0 -1 0 -1 0 1
			fslmaths data_slice0.nii -mul 0 data_slice0.nii
			fslmerge -z data.nii $rawDIR/dwi_peAP.nii data_slice0
		else
			ln -sfv combined_B0s_orig.nii.gz combined_B0s.nii.gz
			ln -sfv ../0_rawdata/dwi_peAP.nii.gz data.nii.gz
		fi
		echo "$EXTRA_Z_SLICE_ADDED" >extra_slice_added.txt
	fi
	
	if [ "`imtest $tuDIR/combined_B0s_fdc.nii.gz`" -eq 0 ]; then
		cd $tuDIR/
		## be prepared to wait ~30 minutes for 4-volumes * 2 each PE-directions (4xFwd+4xRev)
		# pass in the 4-volume uncorrected B0s, acqparams, default config,
		# output from:
		#   -out is two files: 1) field map (_fieldcoeffs.nii), 2) _movpar.txt (head-motion parameters for 2x2vols)
		#   -iout is the corrected 4-volume nifti file (needed for skullstripping next step)
		echo "-- starting topup: `date`, using acqparams.txt file ================>"
		cat acqparams.txt
		echo "<===================="
		TIMER_START=${SECONDS}
		topup --imain=combined_B0s.nii --datain=acqparams.txt --config=${FSLDIR}/etc/flirtsch/b02b0.cnf --out=dwi_fdc --iout=combined_B0s_fdc
		ELAPSED_TIME=$(($SECONDS - $TIMER_START))
		echo "-- finished topup: `date`, elapsed time: $(($ELAPSED_TIME/60)) min, $(($ELAPSED_TIME%60)) sec"
		if [ "`imtest combined_B0s_fdc.nii.gz`" -eq 0 ]; then
			echo "*** ERROR: problem with topup, did not generate output file = combined_B0s_fdc.nii"
			continue
		fi
		echo "-- creating nodif.nii as Tmean of combined_B0s_fdc.nii"
		fslmaths combined_B0s_fdc.nii -Tmean nodif.nii
		echo "-- creating nodif_brain_mask.nii ..."
		bet nodif.nii nodif_brain -f 0.1 -g 0 -m -n
	fi
	
	## ------------- Eddy ----------------------------------------------------------------
	ecDIR="$DDIR/2_eddy"
	## RUN new EDDY
	if [ "`imtest $ecDIR/data_ec.nii.gz`" -eq 0 ]; then
		echo "-- running eddy tool to correct head-motion, eddy current distortion, and field distortion."
		mkdir -p $ecDIR/ && cd $ecDIR/
		ln -sf ../0_rawdata/dwi_peAP.bval bval
		ln -sf ../0_rawdata/dwi_peAP.bvec bvec
		imln ../1_topup/data.nii.gz data.nii.gz
		imln ../1_topup/nodif_brain_mask.nii.gz mask.nii.gz
		/bin/rm -f index.txt acqparams.txt
		NumVols=$(cat bval | wc -w)
		python -c "print '%s'%(' '.join(['1']*${NumVols}))" >index.txt
		cat $tuDIR/acqparams.txt | head -n 1 >acqparams.txt
		echo " ++ starting eddy_openmp: `date`"
		TS=${SECONDS}
		eddy_openmp -v --repol --cnr_maps --imain=data --topup=$tuDIR/dwi_fdc --mask=mask --index=index.txt --acqp=acqparams.txt --bvecs=bvec --bvals=bval --out=data_ec
		ET=$(($SECONDS - $TS))
		echo " ++ finished eddy, Elapsed time = $(($ET/60)) min, $(($ET%60)) sec at `date`"
		if [ "`imtest data_ec.nii.gz`" -eq 0 ]; then
			echo -e "\n*** ERROR: new eddy command failed for $S ...\n"
			continue
		fi
		## create new NODIF as mean of Eddy-Corrected B0s 
		echo " ++ creating new nodif as Tmean of B0s from data_ec.nii, and new nodif_brain_mask"
		B0Vols=$(python -c "x=[str(i) for i,v in enumerate(open('bval','rU').read().split()) if v=='0']; print ','.join(x)")
		fslselectvols -i data_ec.nii -o data_ec_B0s --vols=${B0Vols}
		fslmaths data_ec_B0s -Tmean nodif
		bet nodif nodif_brain -f 0.3 -g 0 -m -n	
	fi
	
	
	## ------- EddyQC --------------------------
	cd $ecDIR/
	if [ ! -d "data_ec.qc" ]; then
		echo "--- running eddyQC command eddy_quad"
		eddy_quad data_ec -idx index.txt -par acqparams.txt -m nodif_brain_mask.nii.gz -b bval 
		if [ -f "data_ec.qc/qc.json" ]; then
			echo " ++ eddy_quad finished successfully"
			if [ -f "${SQUAD_FILEPATH}" -a "`grep '$S' ${SQUAD_FILEPATH}`" == "" ]; then
				echo " +++ appending path='$ecDIR/data_ec.qc' --> ${SQUAD_FILEPATH}"
				echo "$ecDIR/data_ec.qc" >>"${SQUAD_FILEPATH}"
			fi
		fi
	fi
	
		
	## ---------- bias correction  -------------------------------------------------------
	bcDIR="$DDIR/3_biascorr"
	if [ "`imtest $bcDIR/data_ec_biascorr.nii.gz`" -eq 0 ]; then
		echo "---- calculating bias-correction on nodif, to apply to data_ec.nii, starting `date`"
		mkdir -p $bcDIR/ && cd $bcDIR/
		ln -sf ../0_rawdata/dwi_peAP.bval bval
		fslmaths $ecDIR/nodif_brain_mask.nii -bin -mul $ecDIR/nodif.nii nodif_brain.nii
		echo " ++ running fast on nodif_brain to generate bias estimate"
		fast -t 2 -b --nopve -o nodif_fast nodif_brain.nii
		echo " ++ applying bias-estimate, final result = data_ec_biascorr"
		#fslmaths nodif.nii -div nodif_fast_bias.nii nodif_biascorr.nii
		fslmaths $ecDIR/data_ec.nii -div nodif_fast_bias.nii data_ec_biascorr
		echo " ++ creating final nodif, nodif_brain_mask, and diff_mean from data_ec_biascorr.nii"
		B0Vols=$(python -c "x=[str(i) for i,v in enumerate(open('bval','rU').read().split()) if v=='0']; print ','.join(x)")
		fslselectvols -i data_ec_biascorr.nii -o data_ec_B0s --vols=${B0Vols}
		fslmaths data_ec_B0s.nii -Tmean nodif.nii
		bet nodif.nii nodif_brain -f 0.4 -g 0 -m 
		diffVols=$(python -c "x=[str(i) for i,v in enumerate(open('bval','rU').read().split()) if v!='0']; print ','.join(x)")
		fslselectvols -i data_ec_biascorr.nii -o data_ec_biascorr_diffVols --vols=${diffVols}
		fslmaths data_ec_biascorr_diffVols.nii -Tmean -mas nodif_brain_mask.nii diff_mean.nii
	fi
	
	
	## ---------------- registrations to T1w ---------------------------------------------
	regDIR=$DDIR/4_reg
	if [ "`imtest $regDIR/nodif_2acpc.nii.gz`" -eq 0 ]; then
		echo "---- registering DWI nodif to t1_2acpc with epi_reg, starting `date`"
		mkdir -p $regDIR/ && cd $regDIR/
		imln ../3_biascorr/nodif.nii.gz nodif.nii
		imln ../../T1w/T1w_acpc_dc_restore.nii.gz t1.nii
		imln ../../T1w/T1w_acpc_dc_restore_brain.nii.gz t1_brain.nii
		if [ ! -f "$SDIR/T1w/T1w_acpc_dc_restore_wmseg.nii.gz" ]; then
			echo " ++ running FAST on $SDIR/T1w/T1w_acpc_dc_restore_brain.nii to generate wmseg mask for epi_reg.."
			fast -N -t 1 -o $SDIR/T1w/T1w_acpc_dc_restore_fast $SDIR/T1w/T1w_acpc_dc_restore_brain.nii
			fslmaths $SDIR/T1w/T1w_acpc_dc_restore_fast_pve_0.nii.gz -thr 0.5 $SDIR/T1w/T1w_acpc_dc_restore_csfseg.nii.gz
			fslmaths $SDIR/T1w/T1w_acpc_dc_restore_fast_pve_1.nii.gz -thr 0.5 $SDIR/T1w/T1w_acpc_dc_restore_gmseg.nii.gz
			fslmaths $SDIR/T1w/T1w_acpc_dc_restore_fast_pve_2.nii.gz -thr 0.5 $SDIR/T1w/T1w_acpc_dc_restore_wmseg.nii.gz
		fi
		imln ../../T1w/T1w_acpc_dc_restore_wmseg.nii.gz t1_wmseg.nii
		echo " ++ starting flirt nodif -> t1-acpc pre-align"
		flirt -in nodif.nii -ref t1.nii -dof 6 -finesearch 5 -cost normmi -omat dwi_2acpc_prealign.mat -o dwi_2acpc_prealign.nii.gz
		echo " ++ starting flirt nodif -> t1-acpc -bbr"
		flirt -in nodif.nii -ref t1.nii -dof 6 -nosearch -cost bbr -wmseg t1_wmseg.nii -init dwi_2acpc_prealign.mat -omat dwi_2acpc.mat -interp spline -o dwi_2acpc.nii -schedule ${FSLDIR}/etc/flirtsch/bbr.sch
		flirt -in $bcDIR/nodif_brain_mask.nii -ref t1.nii -init dwi_2acpc.mat -applyxfm -interp nearestneighbour -o nodif_brain_mask_2acpc.nii
		fslmaths dwi_2acpc.nii -thr 0 -save nodif_2acpc.nii -mas nodif_brain_mask_2acpc.nii nodif_brain_2acpc.nii
		convert_xfm -omat dwi_2acpc_inv.mat -inverse dwi_2acpc.mat
		flirt -in t1_brain.nii -ref nodif -init dwi_2acpc_inv.mat -applyxfm -o t1_brain_2dwi.nii
		flirt -in t1_wmseg.nii -ref nodif -init dwi_2acpc_inv.mat -applyxfm -o t1_wmseg_2dwi.nii
		## Create QC dwi-t1 registration images here...
	fi	
	
	
	## ---------------- Generate DTI Vectors ---------------------------------------------
	vecDIR=$DDIR/5_vectors
	if [ "`imtest $vecDIR/dti_FA.nii.gz`" -eq 0 ]; then
		echo "--- running DTIFIT on $vecDIR, starting `date`"
		mkdir -p $vecDIR/ && cd $vecDIR/
		imln ../3_biascorr/data_ec_biascorr.nii.gz data.nii
		imln ../3_biascorr/nodif_brain_mask.nii.gz nodif_brain_mask.nii
		ln -sf ../2_eddy/data_ec.eddy_rotated_bvecs bvec
		ln -sf ../0_rawdata/dwi_peAP.bval bval
		dtifit -k data.nii --sse -o dti -m nodif_brain_mask.nii -r bvec -b bval
		fslmaths dti_L1.nii.gz dti_AD.nii
		fslmaths dti_L2.nii.gz -add dti_L3.nii.gz -div 2.0 dti_RD.nii
		flirt -in nodif_brain_mask -ref $regDIR/t1.nii -init $regDIR/dwi_2acpc.mat -applyxfm -interp nearestneighbour -o nodif_brain_mask_2acpc.nii 
		for v in FA AD RD MD L1 L2 L3 MO S0 ; do 
			f="dti_${v}"
			echo " ++ registering $f to t1.nii"
			flirt -in $f -ref $regDIR/t1.nii -init $regDIR/dwi_2acpc.mat -applyxfm -o ${f}_2acpc.nii
			fslmaths ${f}_2acpc.nii -mas nodif_brain_mask_2acpc.nii ${f}_2acpc.nii
		done
		for v in V1 V2 V3 ; do 
			f="dti_${v}"
			echo " ++ registering $f to t1.nii"
			vecreg -i $f -o ${f} -r $regDIR/t1.nii -t $regDIR/dwi_2acpc.mat -m nodif_brain_mask.nii
		done
		echo " ++ registering diff_mean to t1.nii"
		flirt -in ../3_biascorr/diff_mean -ref $regDIR/t1.nii -init $regDIR/dwi_2acpc.mat -applyxfm -interp spline -o diff_mean_2acpc.nii
		fslmaths diff_mean_2acpc.nii -uthr 0 -abs -add 1 -add diff_mean_2acpc.nii -mas nodif_brain_mask_2acpc.nii diff_mean_2acpc
		fslmaths diff_mean_2acpc.nii -thr 700 -bin diff_mean_2acpc_thr700.nii
	fi	
	
	echo "------------ completed DWI processing on $DDIR/, at `date`"
	
done


exit 0
