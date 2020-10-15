# grav3d
3D gravity current code\
Instructions to produce model outputs used in figures 5,6,7,8 of Penney & Copley, "Lateral variations in lower crustal strength control the temporal evolution of mountain ranges: examples from south-east Tibet"\
For further information, or if you would like to adapt or use the code for *any* other purpose, please contact Camilla Penney (cp451@cam.ac.uk) or Alex Copley (acc41@cam.ac.uk).

The main script is grav3d.f - the set up process for using this to run the different models used in the paper is described below, and the boundary conditions and model are described in the paper, with the main equations derived in Pattyn, 2003 (https://doi.org/10.1029/2002JB002329).

# Models    
**symmetric**\
folder	scj0(j coordinate of centre of basin)	srad(radius of basin in m)	bcj0(centre of basin on i=imax)	brad(radius of basin in m)	sich_thick (basal thickness, m) base_change ylength(j coordinate of far end of basin)\
sym_1 	40 	300000. 40 	300000.	15000.  60\
sym_2	50 	450000. 50 	450000. 15000.	80\
sym_3 	60	600000. 60 	600000.	15000.	90	\
sym_4 	50 	450000. 50 	450000. 30000.	80\
sym_5	50 	450000. 50 	450000. 0.	80\
sym_6  50 	450000. 50 	450000. 15000.  80 erode 4mm/yr (1.3e-10 m/s)

**asymmetric**\
					blength(length of rectangular extension)	 sich_thick  \  
asym_1	50 	450000. 50 	450000. 1200000. 15000.	       80 (+ full reflection on i=nx)

# Instructions
* in grav3d.f in this directory change dirname to have the path to where you will run the code \
* create the directory structure by running setup.sh, calls setup.py and shapes.py \
* go into each folder and replace // with /${dir}/ in dirname where dir is e.g. sym_0 \
* change ylength and erodek in grav3d.inp \
* run compile (in this directory, again might need to change paths - compiles all of the grav3d.f s in their respective folders)\
* sbatch run_sym_$x.sh for each x\
* sbatch run_asym_$x.sh for each x\
* outputs are in ?sym_$x/OUT - velocities uuu*,vvv*,www* topography top*, particle locations par* where * is time in seconds\

# What is the code doing?
As described in paper appendix.\

Solving Pattyn 2003 eqn 44 (and equivalent for y) for velocities - though n.b. viscosity is constant in these models, using pgmres \
Solving for topography using eqn. A.5 \

Boundary conditions are as shown in Figure 4 (listed below)\
Now have H fixed on influx (j=1, 65km) and beyond basins (40km)\
u=0 dv/dy=0 on j=1\
u=0 (d2/dx2+d2/dz2)v=rho g/eta ds/dy on on i=1,nptsx j<ylength (equivalent to dv/dx=0 substituted in to equations)\
du/dx=0 dv/dx=0 on i=1,nptsx j>ylength\
dv/dy =0 du/dy=0 on j=nptsy

