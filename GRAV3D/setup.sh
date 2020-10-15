#!/bin/bash

HOMEDIR=`pwd`
i=1
IFS=$'\n'

for line in $(cat ${HOMEDIR}/params_sym.txt)
do
    scj0=`echo $line |awk '{print $1}'`
    srad=`echo $line |awk '{print $2}'`
    bcj0=`echo $line |awk '{print $3}'`
    brad=`echo $line |awk '{print $4}'`
    sich_thick=`echo $line |awk '{print $5}'`
#    echo $scj0,$srad,$bcj0,$brad
    RUNDIR=${HOMEDIR}"/sym_"$i"/"
    mkdir -p $RUNDIR
    ${HOMEDIR}/set_ibase.py $scj0 $srad $bcj0 $brad $sich_thick
    mv ${HOMEDIR}/ibase.in $RUNDIR
    mv ${HOMEDIR}/ibase.xy $RUNDIR
    mv ${HOMEDIR}/zmax.in $RUNDIR
    cp ${HOMEDIR}/grav3d.f $RUNDIR
    cp ${HOMEDIR}/grav3d.inp $RUNDIR
    cd $RUNDIR
    mkdir -p ${RUNDIR}OUT
    
    cp ${HOMEDIR}/particles.in ${RUNDIR}
    
    cd $HOMEDIR
    ((i+=1))
    
done


i=1
for line in $(cat ${HOMEDIR}/params_asym.txt)
do
    scj0=`echo $line |awk '{print $1}'`
    srad=`echo $line |awk '{print $2}'`
    bj0=`echo $line |awk '{print $3}'`
    bxdim=`echo $line |awk '{print $4}'`
    bydim=`echo $line |awk '{print $5}'`
    sich_thick=`echo $line |awk '{print $6}'`
    RUNDIR=${HOMEDIR}"/asym_"$i"/"
    mkdir -p $RUNDIR
    python ${HOMEDIR}/set_ibase.py $scj0 $srad $bj0 $bxdim $bydim $sich_thick
    mv ${HOMEDIR}/ibase.in $RUNDIR
    mv ${HOMEDIR}/ibase.xy $RUNDIR
    mv ${HOMEDIR}/zmax.in $RUNDIR 
    cp ${HOMEDIR}/grav3d.f $RUNDIR
    cp ${HOMEDIR}/grav3d.inp $RUNDIR
    cp ${HOMEDIR}/compile $RUNDIR
    cd $RUNDIR
    mkdir -p ${RUNDIR}OUT
    cp ${HOMEDIR}/particles.in ${RUNDIR}
    
    cd $HOMEDIR
    ((i+=1))
    
done

