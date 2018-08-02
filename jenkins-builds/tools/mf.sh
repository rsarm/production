#!/bin/bash
usage() {
    echo "Usage: $0 <daint-gpu|daint-mc>"
    exit 1;
}

partition=$1
if [ -z $partition ] ;then
    usage
fi
outlog=deps.log

productiondir=../..
if [ "$partition" = "daint-gpu" ];then
    topdir=/apps/daint/UES/jenkins/6.0.UP04/gpu/easybuild
    MODULEPATH=$topdir/modules/all
    jenkinslist=$productiondir/jenkins-builds/6.0.UP04-17.08-gpu
fi

if [ "$partition" = "daint-mc" ];then
    topdir=/apps/daint/UES/jenkins/6.0.UP04/mc/easybuild
    MODULEPATH=$topdir/modules/all
    jenkinslist=$productiondir/jenkins-builds/6.0.UP04-17.08-mc
fi

MODULEPATH=/apps/daint/UES/easybuild/modulefiles:$MODULEPATH
MODULEPATH=/opt/cray/ari/modulefiles:$MODULEPATH
MODULEPATH=/opt/cray/modulefiles:$MODULEPATH
MODULEPATH=/opt/cray/pe/ari/modulefiles:$MODULEPATH
MODULEPATH=/opt/cray/pe/craype/2.5.12/modulefiles:$MODULEPATH
MODULEPATH=/opt/cray/pe/modulefiles:$MODULEPATH
MODULEPATH=/opt/cray/pe/perftools/6.5.1/modulefiles:$MODULEPATH
MODULEPATH=/opt/modulefiles:$MODULEPATH
export MODULEPATH

installed_ebs=`find $topdir/software -name \*.eb 2> /dev/null`
echo $installed_ebs |tr " " "\n" > $outlog

mflist=""
jenkins_eblist=`grep -v \# $jenkinslist |awk '{print $1}' |tr -d " "` 
for jenkins_eb_file in $jenkins_eblist ;do

    jenkins_eb_file_fullpath=`echo $installed_ebs |tr " " "\n" |grep "$jenkins_eb_file"`
    mf=`echo $jenkins_eb_file_fullpath |sed "s-$topdir/software--" |awk -F/ '{print $2"/"$3}'`    

    if [ $mf != "/" ] ;then    
        mflist="$mf $mflist"
    else
        echo "jenkins_eb_file=$jenkins_eb_file"
        echo "jenkins_eb_file_fullpath=$jenkins_eb_file_fullpath"
        echo "mf=$mf"
        echo
    fi
done
echo -e "\n $mflist" >> $outlog
#echo "# --- step1 done"
#exit 0


# -----
# mflist="MVAPICH2/2.2a-GCC-4.9.3-binutils-2.25 MVAPICH2/2.1_cuda_7.0_gdr"
# MVAPICH2/2.1_cuda_7.0_gdr -> mvapich2gdr_gnu/2.1_cuda_7.0 -> cudatoolkit/7.0.28
# MVAPICH2/2.2a-GCC-4.9.3-binutils-2.25 -> GCC/4.9.3-binutils-2.25 -> binutils/.2.25
#                                       -> cudatoolkit/7.0.28  
# -----

outf0=eff0
outf1=eff1
outf2=eff2
tmp0=eff.level0
echo "digraph $HOSTNAME {" > $0.dot

echo > $tmp0
for mf in $mflist ;do
    echo "# Processing $mf ..." |tee -a $outlog
    module show $mf > $outf0 2>&1 
    grep -q "ERROR:105" $outf0 ;rc=$?
    mfn=`echo $mf |cut -d/ -f1`
    echo $mf >> $tmp0
    listofdeps0=`grep " load " $outf0 |awk -Fload '{print $2}' |tr -d " "`
    if [ -n "$listofdeps0" ] ;then

        for deps0 in $listofdeps0 ;do 
            echo "\"$mf\" -> \"$deps0\";"

            # --- sublevel1
            module show $deps0 > $outf1 2>&1
            grep -q "ERROR:105" $outf1 ;rc=$?
            listofdeps1=`grep " load " $outf1 |awk -Fload '{print $2}' |tr -d " "`
            if [ -n "$listofdeps1" ] ;then
                for deps1 in $listofdeps1 ;do
                    echo "\"$deps0\" -> \"$deps1\";"

                    # --- sublevel2
                    module show $deps1 > $outf2 2>&1
                    grep -q "ERROR:105" $outf2 ;rc=$?
                    listofdeps2=`grep " load " $outf2 |awk -Fload '{print $2}' |tr -d " "`
                    if [ -n "$listofdeps2" ] ;then
                        for deps2 in $listofdeps2 ;do
                            echo "\"$deps1\" -> \"$deps2\";"
                        done
                    fi # --- sublevel2

                done
            fi # --- sublevel1

        done
    fi # --- sublevel0

done |sort -u >> $0.dot 

echo '}' >> $0.dot

echo "module load stat"
echo 'export LD_LIBRARY_PATH=/opt/cray/pe/stat/default/lib:$LD_LIBRARY_PATH'
echo "dot -Tpng $0.dot > $0.png"
echo "circo -Teps ./$0.dot > $0.eps"
echo "try tulip too"
#echo "dot -Tjpg $0.dot > $0.jpg"
echo '------------------------------------------------------------------'

#set -x
# iterate through the list of software (=level0)
for l0 in `sort -u $tmp0` ;do

#echo continue;read
    #echo "Listing l0=$l0 ..."
    unset listl1a
    unset listl1b
    unset listl2a
    unset listl2b
    # iterate through the list of deps (=level1)
    listofl1deps=`grep "^\"$l0\" ->" mf.sh.dot |awk -F"->" '{print $2}' |tr -d \;`
    for l1 in $listofl1deps ;do 
        # is this the end ?
        rc=`grep -m1 -q "^$l1 ->" mf.sh.dot;echo $?`
        if [ $rc -ne 0 ] ;then
            # no more dep = end of the chain
            listl1a="${listl1a} $l1 "
        else
            # more dep down the chain = continue parsing
            l1tmp=`grep -m1 "^$l1 ->" mf.sh.dot |awk -F"->" '{printf "%s ",$1}' |tr -d \;`
            listl1b=${listl1b}$l1tmp
        fi        
    done       
    listl1s=`echo $listl1a $listl1b |tr " " "\n" |sort -u |awk '{printf "%s ",$0}'`
    #echo "## l0=$l0: $listl1s"
    echo '------------------------------------------------------------------'

    # iterate through the list of deps'deps (=level2)
    unset listl2s listl2 l2tmp 
    for l1 in $listl1b ;do        
        l2tmp=`grep "^$l1 ->" mf.sh.dot |awk -F"->" '{print $2}' |tr -d \;`
        listl2=${listl2}$l2tmp
        listl2s=`echo $listl2 |tr " " "\n" |sort -u |awk '{printf "%s ",$0}'`
#ok        listofl2deps=`grep "^$l1 ->" mf.sh.dot |awk -F"->" '{print $2}' |tr -d \;`
#ok        for l2 in $listofl2deps ;do
#ok            rc=`grep -m1 -q "^$l2 ->" mf.sh.dot;echo $?`
#ok            if [ $rc -ne 0 ] ;then
#ok                # no more dep = end of the chain
#ok                listl2a="${listl2a} $l2 "
#ok            else
#ok                l2tmp=`grep ^$l2 mf.sh.dot |awk -F"->" '{printf "%s ",$1}' |tr -d \;`
#ok                listl2b=${listl2b}$l2tmp
#ok            fi
#ok        done
#ok        listl2s=`echo $listl2a $listl2b |tr " " "\n" |sort -u |awk '{printf "%s ",$0}'`
        #echo "## l0=$l0: $listl2s"
    done

    listls=`echo $listl1s $listl2s |tr " " "\n" |sort -u |awk '{printf "%s ",$0}' |tr -d \"`
    echo "## l0=$l0: $listls"

done

#set +x
