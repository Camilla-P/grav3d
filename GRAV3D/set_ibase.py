#!/usr/bin/python
#set values of ibase for grav3d.f
import numpy as np
from shapes import rectangle_topo, circ_topo

import sys
#find intervals
with open('grav3d.inp','r') as file_in:
    u=0
    for line in file_in:
        info=line.split('\t')[0]
        if u==0:
            dx=float(info)
        elif u==1:
            dy=float(info)
        u+=1
#print "dx",dx,"dy",dy
#set dimensions
nptsx=100
nptsy=120
print len(sys.argv)


prog_name = sys.argv[0]
#either have nothing on command line in which case take defaults
if len(sys.argv)==1:
    #for rectangular no slip sections
    # i0,j0 are bottom left corner
    #set burma dimensions
    bxdim=400000.
    bydim=200000.
    bi0=80
    bj0=0
    #make a semi circle 
    
    bci0=(nptsx-1)
    bcj0=80
    brad=300000.
    #set sichuan dimensions
    sxdim=400000.
    sydim=400000.
    si0=0
    sj0=80
    #make a semicircle
    sci0=0
    scj0=80
    srad=300000.
    sich_thick=30000.
    #or have two semi circles
elif len(sys.argv)==6:
#sb semi circle on lhs
    sci0=0
    scj0=int(sys.argv[1])
    srad=float(sys.argv[2])
    bci0=nptsx-1
    bcj0=int(sys.argv[3])
    brad=float(sys.argv[4])
    sich_thick=float(sys.argv[5])
#    print "params",sci0,scj0,srad,bci0,bcj0,brad
#or have sichuan semi circle and ibr long
elif len(sys.argv)==7:
    sci0=0
    scj0=int(sys.argv[1])
    srad=float(sys.argv[2])
    
    bj0=int(sys.argv[3])
    bxdim=float(sys.argv[4])
    bydim=float(sys.argv[5])
    sich_thick=float(sys.argv[6])
    bi0=nptsx-1-int(bxdim/dx)
#    print "params",sci0,scj0,srad,bi0,bj0,bxdim,bydim,sich_thick
else:
    print "wrong number of arguments"





#initialise ibase

ibase=np.zeros((nptsx,nptsy))


with open("ibase.in",'w') as file_out1:
    with open("ibase.xy",'w') as file_out2:
        for i in np.arange(0,nptsx,1):
            for j in np.arange(0,nptsy,1):
                
                base_no=circ_topo(i,j,sci0,scj0,srad,dx,dy)
                
                if base_no == 0:
                   ibase[i,j]=0
                else:
#                    print "base",base_no
                    if len(sys.argv)==6 or len(sys.argv)==1:
                        ibase[i,j]=circ_topo(i,j,bci0,bcj0,brad,dx,dy)
                        
                    elif len(sys.argv)==7:
                        ibase[i,j]=rectangle_topo(i,j,bi0,bj0,bxdim,bydim,dx,dy)
                #write out ibase
                file_out1.write('{0:g}\n'.format(ibase[i,j]))
                file_out2.write('{:.0f} {:.0f} {:.0f}\n'.format(i+1,j+1,ibase[i,j]))

# also want sichuan basin to have certain thickness of rigid material at base
zmax=np.zeros((nptsx,nptsy))

with open('zmax.in','w') as file_out:
    for i in np.arange(0,nptsx,1):
        for j in np.arange(0,nptsy,1):
            base_no = circ_topo(i,j,sci0,scj0,srad,dx,dy)
            
            if base_no == 0:
                zmax[i,j]=sich_thick
            else:
                if len(sys.argv)==6 or len(sys.argv)==1:
                    base_no=circ_topo(i,j,bci0,bcj0,brad,dx,dy)
                elif len(sys.argv)==7:
                    base_no=rectangle_topo(i,j,bi0,bj0,bxdim,bydim,dx,dy)

                if base_no == 0:
                    zmax[i,j]=sich_thick
                else:
                    zmax[i,j]=0
            file_out.write('{0:g}\n'.format(zmax[i,j]))
                
