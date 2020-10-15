import os
import numpy as np


def rectangle_topo(i,j,i0,j0,xdim,ydim,dx,dy):
    """
    Function to identify whether i,j coordinates should be no slip for rectangle with bottom left corner i0,j0 and dimensions xdim, ydim. Set to have rounded corners.
    """
    idist=(float(i)-float(i0))*dx
    jdist=(float(j)-float(j0))*dy
    irad=(float(i)-float(i0))*dx-xdim
    
    rad=np.sqrt((irad**2) + (jdist**2))

    if (0<= idist <= xdim and 0 <= jdist<= ydim) or (rad <= ydim and rad<=xdim) :
        return 0
    else:
        return 1

def circ_topo(i,j,i0,j0,rad,dx,dy):
    """
    Function to identify whether i,j coordinates which should have no slip for circle centred on i0,j0 with radius rad
    """
    jdist=((float(j)-float(j0))*dy)**2.
    
    idist=((float(i)-float(i0))*dx)**2.
    cdist=np.sqrt(jdist+idist)
    
    if cdist <= rad :
        return 0
    else:
        return 1
