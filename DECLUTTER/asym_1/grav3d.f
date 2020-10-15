c Please see the README file for details of how to use this code.
c This code is the basis for the modelling results in Penney & Copley,2020
c (in review at G3, preprint https://doi.org/10.31223/osf.io/zxq4t)
c The code as run to produce the models used in figures in that paper can
c     be found in the separate sub-directories.
c If you would like to use this code, please contact:
c Camilla Penney (cp451@cam.ac.uk) or Alex Copley (acc41@cam.ac.uk)
c     to ensure that you don't waste a lot of time.
      program grav3d

      implicit none

      integer*4 nptsx,nptsy,nptsz,NN,iiwk,nz,numproc,xlength,ylength,
     &     npart
c     npts : number of grid points in each direction
c     NN : no. params solved for nptsx*nptsy*nptsz*2 (solve for u and v)
c     npart: number of particles to track (initial locations:particles.in)
      parameter(nptsx=100,nptsy=120,nptsz=20,NN=480000,npart=100)
c     increments
      real*8 dx,dy,dpsi,dt
c     pi
      real*8 pi
c     flow properties
c     rho is crustal density
c     tpm is shortest time to move vertically across a
c     vertical interval anywhere in model domain
      real*8 f,rho,g,t,velmin,erodek,tpm
c     heights + gradients 
      real*8 s(nptsx,nptsy),H(nptsx,nptsy),dH_dx(nptsx,nptsy),
     &      dH_dy(nptsx,nptsy),d2H_dx2(nptsx,nptsy),Smax,topo_init(3),
     &     ds_dx(nptsx,nptsy),d2s_dx2(nptsx,nptsy),hmin,smin,stot,
     &     ds_dy(nptsx,nptsy),d2s_dy2(nptsx,nptsy),db_dy(nptsx,nptsy),
     &     db_dx(nptsx,nptsy),dH_dt(nptsx,nptsy),d2H_dy2(nptsx,nptsy),
     &     sinit

c     velocities 
      real*8 v(nptsx,nptsy,nptsz),u(nptsx,nptsy,nptsz),
     &     w(nptsx,nptsy,nptsz),umax,wmax,uold(nptsx,nptsy,nptsz),
     &     vold(nptsx,nptsy,nptsz)

c     viscosity
      real*8 eta(nptsx,nptsy,nptsz),deta_dx(nptsx,nptsy,nptsz),
     &     deta_dz(nptsx,nptsy,nptsz),deta_dy(nptsx,nptsy,nptsz)

c     volume check
      real*8 Vtot

c     parts of velocity equation
      real*8 a_y(nptsx,nptsy,nptsz), a_x(nptsx,nptsy,nptsz)
     $     ,b_x(nptsx,nptsy,nptsz),dax_dz(nptsx,nptsy,nptsz),
     $     b_y(nptsx,nptsy,nptsz),sol(NN),c_xy(nptsx,nptsy,nptsz),
     &     dax_dy(nptsx,nptsy,nptsz),b(NN),bold(NN)

c     parameters for pgmres
      real*8  droptol,eps
c     fractions
      real*8 a1_4,a2_3,a1_3,a1_5,a1_8

c     parameters for similarity solutions 
      real*8 hinit,height,zed,init_vol(nptsx),h_theo(nptsx,nptsy)
     $     ,phi(nptsx,nptsy),zmax(nptsx,nptsy)
     $     ,eta_N,L(nptsx),dum(nptsx,nptsy),eta_bar,s_theo(nptsx,nptsy)
     $     ,Q_vol,xi(nptsx,nptsy),zeta(nptsx,nptsy),psi(nptsx,nptsy),
     $     rad(nptsx,nptsy),xi_n

      integer*4 nzmax,timings,reset,predif
      integer*4 i,j,k,ibase(nptsx,nptsy),q,nnz,viserr,visit,qmax,
     $     mbloc,iperm(2*NN),kmax(nptsx,nptsy),icount(4),
     $     ierr,lfil,ju(NN),jw(2*NN),im,maxits,iout,wmaxi,wmaxj
     $     ,ierrit,tomx,tnum,visitmax, temperr,terr,sflist(2),tpmi,flat
     $     ,slope,cent,m,n,off,loff,dkr, p

c     tracking particle locations
      real*8 partloc(npart,2) 

      character*32 ts,vs
      character*64 outputfilename
      character*64 dirname

c     parallel stuff (not used)
      integer*4 job,ii,maxmp,lenlist,ik,jj,i1,ko,nl, irow,param(5
     $     ,250),index,rhsindex,nrow,nloc, nnzloc,displs(250)
     $     ,sendcounts(250),offset,gmsize,naloc, myproc,world_group
     $     ,workers,nrhs,tag,nbnd,nproc,type, wksp,alusize,imp,iter
     $     ,icode,itsgmr,anumber,status(10),lwk, its,ipar(16),precon
     $     ,fgmnum,fgmmax
      real*8 tol,sumloc,ddot,residIn,epsgmr,residOut, fpar(16),stime
     $     ,etime,tlim
      real*8 sum

c     pointers..........

      real*8 , ALLOCATABLE :: scaletmp(:),bb(:), iwk2(:),vv(:,:),wk1(:)
     $     ,wk2(:),rhsloc(:),aloc(:),iau(:),alu(:) ,finalsol(:)
     $     ,globalsol(:),aa(:),atmpd(:),rhstmp(:), www(:,:),ww(:)
      real*8 , ALLOCATABLE :: aaa(:),aas(:),atmp(:),c(:)
      integer*4 , ALLOCATABLE :: ir(:),jc(:),ja(:),ia(:),jatmp(:),
     $     iatmp(:),ic(:),iwk(:), riord(:),riordo(:),mask(:),iptro(:)
     $     ,maptmp(:),mapptr(:), link(:),listmp(:),jctmp(:),irtmp(:)
     $     ,gmap(:),ix(:),map(:), ipr(:),proc(:),jb(:),ib(:),list(:)
     $     ,jaloc(:),ialoc(:), jlu(:)

      dirname="///"

      myproc = 1
      open(8,file=trim(dirname)//"grav3d.log")
      flush(8)
      nrow = NN
      nrhs = nrow

c     read in parameters
      open(1,file=trim(dirname)//'grav3d.inp')
      read(1,*)dx
      read(1,*)dy
      read(1,*)f
      read(1,*)sinit
      read(1,*)erodek
c ylength  (this is where boundary condition changes along x=1,nptsx)
      read(1,*) ylength
      close(1)

      a1_4 = 1./4.
      a2_3 = 2./3.
      a1_3 = 1./3.
      a1_5 = 1./5.
      a1_8 = 1./8.

      
      open(10,file=trim(dirname)//'topo_init.out')
      open(21,file=trim(dirname)//'geotherm.out')
      open(22,file=trim(dirname)//'norm.in')
      open(23,file=trim(dirname)//'timout')
c uncomment to start with topography produced by an earlier run
c to make timestamps correct change t (+make sure "run" doesnt delete OUT!)  
c      open(15,file='topo_start.out')
      dkr = 0

      timings = 0
      reset = 10000
c     define pi
      pi=atan(1.)*4.
      write(6,*) "PI:",pi     

      iiwk = NN*40
c size of interval dzeta 
      dpsi = 1./(nptsz-1.)
      
c initial thickness of layer to flow into      
      smin = sinit
      hmin = smin*(f+1.)
      
c      set ibase  0 for no slip, 1 for stress-free
c ibase.in is made by set_ibase.py (as is zmax.in)
      open(1,file=trim(dirname)//'ibase.in')
      do i=1,nptsx,1
         do j=1,nptsy,1
            read(1,*) ibase(i,j)
         enddo
      enddo
      close(1)
c     work out how many of these are along each edge 
      icount(1)=nptsx
      icount(2)=nptsy
      icount(3)=nptsx
      icount(4)=nptsy
      do j=1,nptsy,1
         icount(1)=icount(1)-ibase(1,j)
         icount(3)=icount(3)-ibase(nptsx,j)
      enddo
      do i=1,nptsx,1
         icount(2)=icount(2)-ibase(i,1)
         icount(4)=icount(4)-ibase(i,nptsy)
      enddo
c      write(6,*)"icount",icount
c set thickness of no slip region for sichuan basin - set to 15km
      open(1,file=trim(dirname)//'zmax.in')
      do i=1,nptsx,1
         do j=1,nptsy,1
            read(1,*) zmax(i,j)
         enddo
      enddo
      close(1)
c read in initial locations of particles to track through flow
      open(1,file=trim(dirname)//'particles.in')
      open(2,file=trim(dirname)//'particles.out')
      do i=1,npart,1
         read(1,*) partloc(i,1:2)
      enddo
      close(1)      
      dt = 3.e9                 ! initial timestep size
      qmax = 1000          ! max number of timesteps
           
      
      precon = 1                ! 1 is left, 2 is right
      
      velmin=5.e-19             !minimum velocity to keep in calculations
      
      nzmax = iiwk
      nnz = iiwk
        
      maxits = 5000
      
      eta_bar=1.e22           ! viscosity       

c     pgmres params for velocity calculation (those for topography are inside topow)
      droptol =1.e-15
      im = 20
      iout = 0
      epsgmr =  0.01
      imp = im
      iter = 0
      icode = 0
      eps = 1.e-20
      itsgmr = 30
      lfil = 20
      fgmmax = 10000
      tlim = 300.

c first timestep
      q = 1

C     assuming constant
      rho = 2700.
      g = 9.81
      
      write(8,*)"n_h = ",nptsx,nptsy
      write(8,*)"n_v = ",nptsz
      write(8,*)"NN, iiwk = ",NN,iiwk
      write(8,*)"dx,dy = ",dx,dy
      write(8,*)"dt = ",dt
      write(8,*)"f = ",f
    
      flush(8)
      
      
C     initial topo, s = surface elev, H = thickness
cc     if f isn't 0 (i.e. have isostatic compensation) need to check that hmin is big enough i.e. (f+1)* desired smin
        
      Vtot=0.
      Q_vol=0.
c Smax is the maximum surface elevation above whatever the elevation of 40km thick crust is relative to a column of mantle (smin)
      Smax = 4500.

c     width of starting topography
      xlength = 10
      do i = 1,nptsx,1
         do j = 1,nptsy,1
            s(i,j) = smin 
c uncomment + comment following to start from end of previous run
c            read(15,*) topo_init
c            s(i,j)=topo_init(3)
            if(j.le.xlength)then
             s(i,j)=Smax-((REAL(j)-1.)*((Smax)/REAL(xlength)))-
     &             (REAL(i)/10000.)+smin
             if(s(i,j).lt.smin)then
               s(i,j) = (smin-((REAL(i)+REAL(j))/10000.))
             endif
   
cc            write(6,*) i,j,s(i,j)
             if(s(i,j).lt.smin)then
                s(i,j) = (smin-((REAL(i)+REAL(j))/10000.))
            endif
        
cc*********** N.B. make sure s(i,j) always > 0.********
          else
             s(i,j) = (smin-((REAL(i)+REAL(j))/10000.))

             
         endif
         
                        
           H(i,j) = s(i,j)*(f+1.)
           Vtot=Vtot+dx*dy*H(i,j)
           if(s(i,j).le.2.) write(6,*)"s",i,j,s(i,j)
           if(H(i,j).le.2.) write(6,*)"H",i,j,H(i,j) 


      enddo
      
      enddo    

      do i = 1,nptsx,1
        do j =1,nptsy,1
          write(10,*)i,j,s(i,j),H(i,j)
        enddo
      enddo
      close(10)
c      close(15)
     
C     input the viscosity
      
      do i = 1,nptsx,1
        do j = 1,nptsy,1
          do k = 1,nptsz,1
             eta(i,j,k) = eta_bar
          enddo
        enddo
      enddo  
      
      
      do i = 1,nptsx,1
        do j = 1,nptsy,1
          do k = 1,nptsz,1
            u(i,j,k) = 0.
            v(i,j,k) = 0.
            w(i,j,k) = 0.
            uold(i,j,k) = 0.
            vold(i,j,k) = 0.
          enddo
        enddo
      enddo
      
      t= 0.
      
CCCCCCCCCCCCCCCCCCCCCCCstart of each timestep CCCCCCCCCCCCCCCCCCCCCC
      do 121 q = 1,qmax,1
c     write(8,*)q,myproc," start timestep"
        
        write(8,*)
        write(8,*)
        flush(8)
        
c     goto 333
        umax = 0.
        wmax = 0.
        tpm = 1.e30 
c     tpm is shortest time to move vertically across a
c     vertical interval anywhere in model domain
        do i = 1,nptsx,1
          do j = 1,nptsy,1
            do k = 1,nptsz,1
              if(abs(u(i,j,k)).gt.umax)umax = abs(u(i,j,k))
              if(abs(v(i,j,k)).gt.umax)umax = abs(v(i,j,k))
              if(H(i,j)*dpsi/abs(w(i,j,k)).lt.tpm)then
                tpm = H(i,j)*dpsi/abs(w(i,j,k))
                tpmi = i
              endif
              if(w(i,j,k).gt.wmax)then
                wmax = w(i,j,k)
                wmaxi = i
              endif
            enddo
          enddo
        enddo
        write(8,*)"u/v max = ",umax," wmax = ",wmax," wmaxi = ",wmaxi
c     not doing the following for the first timestep
c     for stability the time interval can't be longer than the time
c     to move across a grid rectangle - set it to 1/3 of this to be safe
        if(q.gt.1)then
          dt = (dy/umax)/(3.)
          write(8,*)"x/y = ",(dx/umax)/2.5," z = ",tpm/2.5,tpmi
       endif
c     advance timestep
       t=t+dt
      if(t.gt.2.e17) goto 3
 333    continue
        
c        if(q.eq.1)t = t+dt
c     write 6 means write to screen
        write(6,119)"start of timestep t = ",t/31556926e6," Myr, dt = "
     $       ,dt/31556926e6," Myr, vmax = ",umax*31556926000.
     $       ," mm/yr, q = ",q
 119    format(a22,f8.2,a11,f8.4,a13,f8.2,a12,i5)
        flush(8)
        ierrit = 0
        
        
        goto 436
 435    continue

 436    continue
c not used - parallel stuff
       visit = 1               ! ... so all the other processors also know...
 123    continue
C     CCCCCCCCCCCCC start processor one only not used CCCCCCCCCCCCCC
        
        
 124    continue
        
C        write(8,*)"viscosity iteration = ",visit
        flush(8)
        
CCCCCCCCCCCCCCCCCCCCCCCCCC start velocity calculation CCCCCCCCCCC
ccc debugging
c check for accidental negative topography
        do i=1,nptsx,1
           do j=1,nptsy,1
              if(H(i,j).le.0.)then
                 write(6,*)i,j,H(i,j),"H",q
                 goto 3
              endif
          enddo
        enddo
c     calculate gradients
        call gradcalc2o(nptsx,nptsy,nptsz,s,ds_dx,ds_dy,d2s_dx2,
     &       d2s_dy2,H,dH_dx,dH_dy,d2H_dx2,d2H_dy2,eta,deta_dx,
     &       deta_dy,deta_dz,a_x,a_y,b_x,b_y,c_xy,dax_dy,dax_dz,
     &       dx,dy,dpsi,f,db_dx,db_dy)

ccc debugging
        do i = 1,nptsx,1
           do j = 1,nptsy,1
              do k = 1,nptsz,1
                 if(eta(i,j,k).ne.eta(i,j,k))write(6,*)"eta",eta(i,j,k)
                 if(deta_dx(i,j,k).ne.deta_dx(i,j,k))then
                    write(6,*)i,j,k ,"deta_dx",deta_dx(i,j,k)
                    goto 3
                 endif
                 if(deta_dy(i,j,k).ne.deta_dy(i,j,k))write(6,*)"deta_dy"
                 if(deta_dz(i,j,k).ne.deta_dz(i,j,k))write(6,*)"deta_dz"
                 if(a_x(i,j,k).ne.a_x(i,j,k))write(6,*)"a_x"
                 if(b_x(i,j,k).ne.b_x(i,j,k))write(6,*)"b_x"
                 if(a_y(i,j,k).ne.a_y(i,j,k))write(6,*)"a_y"
                 if(b_y(i,j,k).ne.b_y(i,j,k))write(6,*)"b_y"
                 if(c_xy(i,j,k).ne.c_xy(i,j,k))write(6,*)"c_xy"
              enddo
              if(ds_dx(i,j).ne.ds_dx(i,j))write(6,*)"ds_dx"
              if(ds_dy(i,j).ne.ds_dy(i,j))write(6,*)"ds_dy"
              if(db_dx(i,j).ne.db_dx(i,j))write(6,*)"db_dx"
              if(db_dy(i,j).ne.db_dy(i,j))write(6,*)"db_dy"
              if(H(i,j).ne.H(i,j))write(6,*)"H",i,j
           enddo
        enddo




        allocate(aaa(iiwk))
        allocate(ir(iiwk))
        allocate(jc(iiwk))
c zmax sets "basal thickness" - calculate what k value this corresponds to
c (changes at each timestep because of height scaling)        
        do i=1,nptsx,1
           do j=1,nptsy,1
              kmax(i,j) = INT(1.+ 
     &             ((zmax(i,j))/(H(i,j)*dpsi)))
c              if(i.lt.10)then
c                 write(6,*) kmax(i,j),i,j
c              endif
              enddo
           enddo
c     acalc sets up matrix on LHS of velocity equations
         write(*,*) "Start of acalc"
        call acalc(nptsx,nptsy,nptsz,eta,deta_dx,deta_dy,deta_dz,
     &       a_x,a_y,b_x,b_y,c_xy,dx,dy,dpsi,NN,ds_dx,ds_dy,H,db_dx,
     &       db_dy,ibase,aaa,ir,jc,nnz,hmin,f,s,smax,ylength,kmax)
c     ylength is location of centre of noslip patches - where to transition to diffusion
         write(*,*) "end of acalc"
        if(visit.eq.1)write(8,*)"nnz = ",nnz," iiwk = ",iiwk

cc debugging
        do i = 1,iiwk,1
           if(aaa(i).ne.aaa(i))then
              write(6,*)"aaa",i,NN,nnz,aaa(i)
              goto 3
           endif
           if(jc(i).ne.jc(i))write(6,*)"jc",i
           if(jc(i).gt.iiwk)write(6,*)"jc big",i
           if(ir(i).ne.ir(i))write(6,*)"ir",i
           if(ir(i).gt.NN)write(6,*)"ir big",i
        enddo


        flush(8)

C     create the RHS vector b...
c     ptr_b = malloc(NN*8)

        if(visit.eq.1)then
           write(*,*) "Start of bcalc"
          call bcalc(b,nptsx,nptsy,nptsz,rho,g,ds_dx,ds_dy,NN,f,
     &          H,s,hmin,eta,uold,vold,q,ibase,
     &          smax,ylength,kmax)
           write(*,*) "end of bcalc"
          write(8,*)"bcalc"
          flush(8)
          do i = 1,NN,1
             if(b(i).ne.b(i))write(6,*)"b",i
             bold(i) = b(i)
          enddo
        else
          do i = 1,NN,1
            b(i) = bold(i)
          enddo
        endif
      
        allocate(aas(iiwk))
        allocate(ja(iiwk))
        allocate(ia(NN+1)) 
        



c convert a from coordinate to compressed sparse row format 
c         write(*,*) "Start of acoocsr"
        call acoocsr(NN,nnz,aaa,ir,jc,aas,ja,ia)
c         write(*,*) "end of acoocsr"

cc debugging
        do i = 1,iiwk,1
           if(aas(i).ne.aas(i))then
              write(6,*)"aas",i,NN,nnz,aas(i)
              goto 3
           endif
           if(ja(i).ne.ja(i))write(6,*)"ja",i
           if(ia(i).ne.ia(i))write(6,*)"ia",i
        enddo


        job = 0
        deallocate(aaa)
        deallocate(ir)
        deallocate(jc)
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCstart making symmetric
        allocate(c(iiwk))
        allocate(jc(iiwk))
        allocate(ic(NN+1))
        allocate(iwk(NN))
        allocate(atmp(iiwk))
        allocate(jatmp(iiwk))
        allocate(iatmp(NN+1))
c     convert compressed sparse row to compressed sparse column
c        write(*,*) "Start of acsrcsc"
        call acsrcsc(NN,job,1,aas,ja,ia,atmp,jatmp,iatmp)
c        write(*,*) "end of acsrcsc"
        do i = 1,iatmp(NN+1)-1
          atmp(i) = 0.d0
        enddo
        do i = 1,nnz
          if(aas(i).ne.aas(i)) write(6,*) "aas",i
          if(ja(i).ne.ja(i)) write(6,*) "ja",i
       enddo
        job = 1
        ii = 2*nnz
c        write(*,*) "Start of aaplb"
        call aaplb(NN,NN,job,aas,ja,ia,atmp,jatmp,iatmp,
     &       c,jc,ic,ii,iwk,ierr)
c        write(*,*) "end of aaplb"
        nnz = ic(NN+1)-1
        do i = 1,NN + 1
          ia(i) = ic(i)
          if(ia(i).ne.ia(i)) write(6,*) "ia",i
        enddo
        do i = 1,nnz
          aas(i) = c(i)
          ja(i) = jc(i)
          if(aas(i).ne.aas(i)) write(6,*) "aas",i
          if(ja(i).ne.ja(i)) write(6,*) "ja",i
       enddo
        
        
        deallocate(atmp)
        deallocate(iatmp)
        deallocate(jatmp)
        deallocate(c)
        deallocate(jc)
        deallocate(ic)
        deallocate(iwk)

cCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCend making symmetric
c        allocate(aa(iiwk))
c        do i = 1,nnz,1
c          aa(i) = (aas(i))
cc     write(6,*)aa(i)
c        enddo
c        deallocate(aas)
cCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCstart scaling
        allocate(scaletmp(NN))
c scale rows to have L2 norm =1
        job = 1
c        write(*,*) "Start of aroscal"
        call aroscal(NN,job,2,aas,ja,ia,scaletmp,aas,ja,ia,ierr)
c        write(*,*) "end of aroscal"
        if (ierr .ne. 0) then
          write (*,*) 'returned ierr .ne. 0 in roscal',ierr
        endif
        do i=1, NN         
           b(i)=b(i)*scaletmp(i)
        end do
c scale columns 
c        write(*,*) "Start of acoscal"
        call acoscal(NN,job,2,aas,ja,ia,scaletmp,aas,ja,ia,ierr)
c        write(*,*) "end of acoscal"
        if (ierr .ne. 0)
     &       write (*,*) 'returned ierr .ne. 0 in coscal',ierr
        
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCend scaling
cc debugging
        do i = 1,iiwk,1
           if(aas(i).ne.aas(i))then
              write(6,*)"aas",i,NN,nnz,aas(i)
              goto 3
           endif
           if(ja(i).ne.ja(i))write(6,*)"ja",i
           if(ia(i).ne.ia(i))write(6,*)"ia",i
           if(i.le.NN)then
              if(b(i).ne.b(i))write(6,*)"b",i
           endif
        enddo
        allocate(alu(iiwk))
        allocate(jlu(iiwk))
        allocate(ww(NN+1))
c LU factorisation 
        write(*,*) "Start of ilut"
        call ilut(NN,aas,ja,ia,lfil,droptol,alu,jlu,ju,iiwk,ww,jw,ierr)
        write(*,*) "end of ilut"
        write(6,*)"ilut ierr = ",ierr
c     if(ierr.ne.0) pause 'ilut ierr .ne. 0'
        iout = 6
c im is size of Krylov subspace
        im = 20
        write(6,*)"iteratively solving"
c sol is the solution of the velocity equations - set to (scaled) previous velocities to improve stability (or try to!)
        do i = 1,nptsx,1
          do j = 1,nptsy,1
             do k = 1,nptsz,1
                sol((2*k)-1 +((j-1)*2*nptsz)+(i-1)*2*nptsz*nptsy) = 
     &               u(i,j,k)/scaletmp((2*k)-1 +
     &               ((j-1)*2*nptsz)+(i-1)*2*nptsz*nptsy)
                sol((2*k) +((j-1)*2*nptsz)+(i-1)*2*nptsz*nptsy) = 
     &               v(i,j,k)/scaletmp((2*k) +(
     &               (j-1)*2*nptsz)+(i-1)*2*nptsz*nptsy)

             enddo
          enddo
       enddo
       do i = 1,NN,1
          if(b(i).ne.b(i))write(6,*)"b",i
       enddo
cc debugging
        do i = 1,iiwk,1
           if(aas(i).ne.aas(i))then
              write(6,*)"aas",i,NN,nnz,aas(i)
              goto 3
           endif
           if(ja(i).ne.ja(i))write(6,*)"ja",i
           if(ia(i).ne.ia(i))write(6,*)"ia",i
           if(ju(i).ne.ju(i))write(6,*)"ju",i
           if(jlu(i).ne.jlu(i))write(6,*)"jlu",i
           if(alu(i).ne.alu(i))write(6,*)"alu",i
        enddo
C     iteratively solve the linear system... (from SPARSKIT2)
        write(*,*) "Start of pgmres"
        call pgmres(NN,im,b,sol,eps,maxits,iout,
     &       aas,ja,ia,alu,jlu,ju,ierr)
        write(*,*) "end of pgmres"
        write(6,*)"pgmres ierr = ",ierr
c        if(ierr.ne.0) goto 3
        do i = 1,NN,1
          sol(i)=sol(i)*scaletmp(i)
        enddo
        deallocate(scaletmp)

c-----------------------------------------------------------------------
c     D O N E 
c-----------------------------------------------------------------------
C     output the results...
        do i = 1,nptsx,1
          do j = 1,nptsy,1
            do k = 1,nptsz,1
            u(i,j,k) = sol( ((2*k)-1) + ((j-1)*(nptsz*2)) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz))
              v(i,j,k) = sol( ((2*k)) + ((j-1)*(nptsz*2)) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz))
            enddo
          enddo
        enddo



        deallocate(alu)
        deallocate(jlu)
        deallocate(ww)
        deallocate(aas)
        deallocate(ja)
        deallocate(ia)
       

c----------write guesses ---------------
        open(1,file=trim(dirname)//"uguess")
        open(2,file=trim(dirname)//"vguess")
        do i = 1,nptsx,1
          do j = 1,nptsy,1
            do k = 1,nptsz,1
c zed - height above base at -b
               zed = ((-H(i,j)/(f+1.))*(f)) +(k-1)*H(i,j)/(nptsz
     $                   -1.)
c     i,j,z,u,analytic u for 2d lubrication,k
               write(1,*)i,j,zed,u(i,j,k),k
               write(2,*)i,j,zed,v(i,j,k),k
            enddo
          enddo
        enddo
        close(1)
        close(2)


c----------------------------------------



        visit = visit + 1
        
        if(mod(q,reset).ne.0)then
          if(visit.eq.visitmax)goto 456
        else
          if(visit.eq.int(visitmax*2))goto 456
        endif

C        if(viserr.eq.1)goto 123
C        ierrit = 0

 456    continue
        if(q.eq.1)then
          visitmax = int(visit/1.5)
          if(visitmax.lt.10)visitmax = 10
        endif
       
C 4444   continue
        
        
        if(myproc.eq.1)write(8,*)"calculating time evolution"
        if(myproc.eq.1)flush(8)
c check for very small velocities and set to zero
        do i=1,nptsx,1
           do j=1,nptsy,1 
              do k=1,nptsz,1
                 if(ABS(u(i,j,k)).lt.velmin) u(i,j,k)=0.
                 if(ABS(v(i,j,k)).lt.velmin) v(i,j,k)=0.
                 if(ABS(w(i,j,k)).lt.velmin) w(i,j,k)=0.
              enddo
           enddo
        enddo
C     calculate new topo...


        call topow(nptsx,nptsy,nptsz,u,v,w,dx,dy,dpsi,dt,s,H,f,dH_dt,
     $       a_x,a_y,ds_dx,ds_dy,dH_dx,dH_dy,hmin,hinit,
     $       q,ylength,height,ierr,ibase,icount)
c     erosion
        call  erode(nptsx,nptsy,H,s,dx,dy,dt,erodek,f)  
c 444   continue
cc determine new particle locations here
c if 1st timestep convert from ijk input
        if(q.eq.1)then
           do i = 1,npart,1
              partloc(i,1)=(partloc(i,1)-1.)*dx
              partloc(i,2)=(partloc(i,2)-1.)*dy
           enddo
        endif

        call move_parts(nptsx,nptsy,nptsz,partloc,
     &       dx,dy,u,v,dt,npart,velmin)       



ccccccccccccc         
       if(MOD(q,1).eq.0)then
         write(8,*)"writing outputs"
         flush(8)
CCCCCCCCCCCCCCCCCCCrunning outputs CCCCCCCCCCCCCCCCc
         open(1,file=trim(dirname)//'u.out')
         open(2,file=trim(dirname)//'v.out')
         open(3,file=trim(dirname)//'w.out')
         do i = 1,nptsx,1
           do j = 1,nptsy,1
             do k = 1,nptsz,1
c     i,j, z,u,k
          write(1,*)i,j,((-H(i,j)/(f+1.))*(f)) +(k-1)*H(i,j)/(nptsz-1.),
     &              u(i,j,k),k
          write(2,*)i,j,((-H(i,j)/(f+1.))*(f)) +(k-1)*H(i,j)/(nptsz-1.),
     &              v(i,j,k),k
          write(3,*)i,j,((-H(i,j)/(f+1.))*(f)) +(k-1)*H(i,j)/(nptsz-1.),
     &              w(i,j,k),k

             enddo

           enddo
         enddo
         close(1)
         close(2)
         close(3)
         
     

        
         open(1,file=trim(dirname)//'topo_run.out')
         do i = 1,nptsx,1
           do j = 1,nptsy,1
             stot = stot + s(i,j)
             write(1,*)i,j,s(i,j),H(i,j),t
     &            ,L(i)
           enddo
         enddo
         close(1)
         

c 595     continue
       endif
CCCCCCCCCCCCCCCCCCCwriting permanent outputs CCCCCCCCCCCCCCCCc
c     do tnum = 1,tomx,1
c     if(t.ge.timout(tnum).and.t-dt.lt.timout(tnum))then
       write(8,*)MOD(q,10)
       flush(8)
       if(MOD(q,10).eq.0)then
         write(8,*)t
         flush(8)
         write(ts,'(e12.6)')t
         
C     TOPO
         outputfilename=
     &        trim(dirname)//'OUT/top0000000000000'
         outputfilename((LNBLNK(outputfilename)-12):
     &        LNBLNK(outputfilename))=ts(1:12)
         open(1,file=outputfilename)
         do i = 1,nptsx,1
           do j = 1,nptsy,1
             stot = stot + s(i,j)
             write(1,*)i,j,s(i,j)
           enddo
         enddo
         close(1)
C     U and V
         outputfilename=
     &        trim(dirname)//'OUT/uuu0000000000000'
         outputfilename((LNBLNK(outputfilename)-12):
     &        LNBLNK(outputfilename))=ts(1:12)
         open(1,file=outputfilename)
         outputfilename=
     &        trim(dirname)//'OUT/vvv0000000000000'
         outputfilename((LNBLNK(outputfilename)-12):
     &        LNBLNK(outputfilename))=ts(1:12)
         open(2,file=outputfilename)
         outputfilename=
     &        trim(dirname)//'OUT/www0000000000000'
         outputfilename((LNBLNK(outputfilename)-12):
     &        LNBLNK(outputfilename))=ts(1:12)
         open(3,file=outputfilename)
         do i = 1,nptsx,1
           do j = 1,nptsy,1
             do k = 1,nptsz,1
               write(1,*)i,j,((-H(i,j)/(f+1.))*(f)) +(k-1)*H(i,j)/
     &              (nptsz-1.),u(i,j,k),k
               write(2,*)i,j,((-H(i,j)/(f+1.))*(f)) +(k-1)*H(i,j)/
     &              (nptsz-1.),v(i,j,k),k
               write(3,*)i,j,((-H(i,j)/(f+1.))*(f)) +(k-1)*H(i,j)/
     &              (nptsz-1.),w(i,j,k),k
             enddo
           enddo
         enddo
         close(1)
         close(2)
         close(3)
c particle locations 
         outputfilename=
     &        trim(dirname)//'OUT/par0000000000000'
         outputfilename((LNBLNK(outputfilename)-12):
     &        LNBLNK(outputfilename))=ts(1:12)
         open(1,file=outputfilename)
         do i = 1,npart,1
            if((int(partloc(i,1)/dx)+1).le.nptsx)then
               if((int(partloc(i,2)/dy)+1).le.nptsy)then
                  write(1,*)i,int(partloc(i,1)/dx)+1,
     &             int(partloc(i,2)/dy)+1,s(int(partloc(i,1)/dx)+1,
     &                 int(partloc(i,2)/dy)+1)
               else
                  write(1,*)i,partloc(i,1:2),5000
               endif
            else
               write(1,*)i,partloc(i,1:2),5000
            endif
         enddo
         close(1)

       

       endif
c     enddo
       
       
CCCCCCCCCCCCCCCCCCend output CCCCCCCCCCCCCCCCCCCCCCCCCC
c end program if topow generated negative topography
c (but after writing to file so I can see what's happened)
       if(ierr.ne.0) goto 3
       
       if(myproc.eq.1)close(93)
c       if(t.gt.1.5e16)goto 3
 121  continue
 3    continue
      close(8)

      stop
      end







CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
CCCCCCCCCCCCCCCCCCCCCCCCC subroutines CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC

CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
      subroutine check_mass(Vtot,H,vav,dx,dy,nptsx,nptsy,nptsz,dt)
c subroutine to check whether increase in mass (actually volume) in a timestep
c is greater than the amount of material which has entered the domain
      integer*4 i,j,k,nptsx,nptsy,nptsz
      real*8 Vtot,H(nptsx,nptsy),vav(nptsx),dx,dy,dt,Vtot_new
      real*8 new_mat,v(nptsx,nptsy,nptsz)
      
      new_mat=0.
      Vtot_new=0.
      vav=0.
           
           do i = 1,nptsx,1
             
                 do k = 1,nptsz,1
                    if(k.eq.1.or.k.eq.nptsz)then
                       vav(i) = vav(i) + (v(i,1,k)*0.5)
                    else
                       vav(i) = vav(i) + v(i,1,k)
                    endif
                 enddo
                 vav(i) = vav(i)/(nptsz-1.)
              enddo
           
      do i=1,nptsx,1
         do k=1,nptsz,1
            new_mat=new_mat+(H(i,1)*dt*vav(i)*dx)
            do j=1,nptsy,1
               Vtot_new=Vtot_new+(H(i,j)*dx*dy)
            enddo
         enddo
      enddo
      if((Vtot_new-Vtot).gt.new_mat)then
          write(6,*) "volume increase greater than input",Vtot
     &        ,Vtot_new,new_mat
      endif
      Vtot=Vtot_new

      return
      end

      subroutine move_parts(nptsx,nptsy,nptsz,loc,dx,dy,
     &     u,v,dt,npart,velmin)
c subroutine to move a particle at a particular location to its new location
c     at t=t+dt - only moves particles along the surface
c n.b. this routine is in place so the locijk which is returned is the new one
      integer*4 npart,i,nptsx,nptsy,nptsz,locijk(npart,2)
      real*8 loc(npart,2),u(nptsx,nptsy,nptsz),v(nptsx,nptsy,nptsz)
      real*8 dx,dy,dt,velmin
      real*8 loc_test(npart,3)

c     locijk is particle position in ijk coordinates
c     convert to 
      loc_test=0.
      do i=1,npart,1
         locijk(i,1)=int(loc(i,1)/dx)+1
         locijk(i,2)=int(loc(i,2)/dy)+1
         
         
c     check whether particles are in bounds before updating locs
         if(locijk(i,1).le.nptsx)then
            if(locijk(i,2).le.nptsy)then
c     now update the particles' locations 
               
                  if(abs(u(locijk(i,1),locijk(i,2),
     &              nptsz)).gt.velmin)then
                     loc_test(i,1)=loc(i,1)+dt*u(locijk(i,1),
     &                    locijk(i,2),nptsz)
                  else
                     loc_test(i,1)=loc(i,1)
                  endif
                  if(abs(v(locijk(i,1),locijk(i,2),
     &                 nptsz)).gt.velmin)then
c     write(6,*) "v",v(locijk(i,1),locijk(i,2),
c     &        locijk(i,3))
                     loc_test(i,2)=loc(i,2)+dt*v(locijk(i,1),
     &                    locijk(i,2),nptsz)
                  else
                     loc_test(i,2)=loc(i,2)
                  endif
                  
                  loc(i,1:2)=loc_test(i,1:2)
               
               endif
            endif

            
         enddo
         

         return
         end
      

      subroutine erode(nptsx,nptsy,H,s,dx,dy,dt,erodek,f)
      implicit none
      integer*4 nptsx,nptsy,i,j
      real*8 H(nptsx,nptsy),s(nptsx,nptsy),dx,dy,dt,erodek,f
      real*8 ds_dx(nptsx,nptsy),ds_dy(nptsx,nptsy),ds_off1(nptsx,nptsy)
      real*8 ds_off2(nptsx,nptsy),dsmax(nptsx,nptsy)
      
      dsmax=0.

      do i=1,nptsx,1
         do j=1,nptsy,1
            if(i.eq.1.and.j.eq.1)then
               ds_dx(i,j)=(s(i+1,j)-s(i,j))/(dx)
               ds_dy(i,j)=(s(i,j+1)-s(i,j))/(dy)
               ds_off1(i,j)=(s(i+1,j+1)-s(i,j))/(
     &              SQRT((dx**2.)+(dy**2.)))
               ds_off2(i,j)=0.
            elseif(i.eq.nptsx.and.j.eq.nptsy)then
               ds_dx(i,j) = (s(i,j)-s(i-1,j))/(dx)
               ds_dy(i,j)=(s(i,j)-s(i,j-1))/(dy)
               ds_off1(i,j)=(s(i,j)-s(i-1,j-1))/(
     &              SQRT((dx**2.)+(dy**2.)))
               ds_off2(i,j)=0.
            elseif(i.eq.nptsx.and.j.eq.1)then
               ds_dx(i,j) = (s(i,j)-s(i-1,j))/(dx)
               ds_dy(i,j)=(s(i,j+1)-s(i,j))/(dy)
               ds_off1(i,j)=(s(i-1,j+1)-s(i,j))/(
     &              SQRT((dx**2.)+(dy**2.)))
               ds_off2(i,j)=0.
            elseif(i.eq.1.and.j.eq.nptsy)then
               ds_dx(i,j) = (s(i+1,j)-s(i,j))/(dx)
               ds_dy(i,j)=(s(i,j)-s(i,j-1))/(dy)
               ds_off1(i,j)=(s(i,j)-s(i+1,j-1))/(
     &              SQRT((dx**2.)+(dy**2.)))
               ds_off2(i,j)=0.
            elseif(i.eq.1)then
c     use forward difference at edge
                ds_dx(i,j)=(s(i+1,j)-s(i,j))/(dx)
                ds_dy(i,j)=(s(i,j+1)-s(i,j-1))/(2.*dy)
                ds_off1(i,j)=(s(i+1,j+1)-s(i,j))/(
     &              SQRT((dx**2.)+(dy**2.)))
                ds_off2(i,j)=(s(i,j)-s(i+1,j-1))/(
     &              SQRT((dx**2.)+(dy**2.)))
            elseif(i.eq.nptsx)then
c     use backwards difference at far edge
               ds_dx(i,j) = (s(i,j)-s(i-1,j))/(dx)
               ds_dy(i,j)=(s(i,j+1)-s(i,j-1))/(2.*dy)
               ds_off1(i,j)=(s(i-1,j+1)-s(i,j))/(
     &              SQRT((dx**2.)+(dy**2.)))
                ds_off2(i,j)=(s(i,j)-s(i-1,j-1))/(
     &              SQRT((dx**2.)+(dy**2.)))
            elseif(j.eq.1)then
               ds_dy(i,j)=(s(i,j+1)-s(i,j))/(dy)
               ds_dx(i,j)=(s(i+1,j)-s(i-1,j))/(2.*dx)
               ds_off1(i,j)=(s(i+1,j+1)-s(i,j))/(
     &              SQRT((dx**2.)+(dy**2.)))
               ds_off2(i,j)=(s(i-1,j+1)-s(i,j))/(
     &              SQRT((dx**2.)+(dy**2.)))
            elseif(j.eq.nptsy)then
               ds_dy(i,j)=(s(i,j)-s(i,j-1))/(dy)
               ds_dx(i,j)=(s(i+1,j)-s(i-1,j))/(2.*dx)
               ds_off1(i,j)=(s(i,j)-s(i-1,j-1))/(
     &              SQRT((dx**2.)+(dy**2.)))
               ds_off2(i,j)=(s(i,j)-s(i+1,j-1))/(
     &              SQRT((dx**2.)+(dy**2.)))
            else
               ds_dy(i,j)=(s(i,j+1)-s(i,j-1))/(2.*dy)
               ds_dx(i,j)=(s(i+1,j)-s(i-1,j))/(2.*dx)
               ds_off1(i,j)=(s(i+1,j+1)-s(i-1,j-1))/(2.*
     &              SQRT((dx**2.)+(dy**2.)))
               ds_off2(i,j)=(s(i-1,j+1)-s(i+1,j-1))/(2.*
     &              SQRT((dx**2.)+(dy**2.)))
            endif
                                   
            if(abs(ds_dy(i,j)).gt.abs(ds_dx(i,j)))then
               dsmax(i,j)=abs(ds_dy(i,j))
            else
               dsmax(i,j)=abs(ds_dx(i,j))
            endif
               
            if(abs(ds_off1(i,j)).gt.abs(dsmax(i,j)))then
               dsmax(i,j)=abs(ds_off1(i,j))
            endif
            
            if(abs(ds_off2(i,j)).gt.abs(dsmax(i,j)))then
               dsmax(i,j)=abs(ds_off2(i,j))
            endif
            
            s(i,j)=s(i,j)-erodek*dt*abs(dsmax(i,j))
            H(i,j)=s(i,j)*(f+1.)
         enddo
      enddo
      return
      end



      subroutine gradcalc2o(nptsx,nptsy,nptsz,s,ds_dx,ds_dy,d2s_dx2,
     &     d2s_dy2,H,dH_dx,dH_dy,d2H_dx2,d2H_dy2,eta,deta_dx,
     &     deta_dy,deta_dz,a_x,a_y,b_x,b_y,c_xy,dax_dy,dax_dz,
     &     dx,dy,dpsi,f,db_dx,db_dy)
      implicit none
      integer*4 nptsx,nptsy,nptsz
      integer*4 i,j,k
      real*8 s(nptsx,nptsy),ds_dx(nptsx,nptsy),ds_dy(nptsx,nptsy)
      real*8 d2s_dx2(nptsx,nptsy),H(nptsx,nptsy),d2s_dy2(nptsx,nptsy)
      real*8 dH_dx(nptsx,nptsy),d2H_dx2(nptsx,nptsy),dH_dy(nptsx,nptsy)
      real*8 d2H_dy2(nptsx,nptsy),eta(nptsx,nptsy,nptsz)
      real*8 deta_dx(nptsx,nptsy,nptsz),deta_dy(nptsx,nptsy,nptsz)
      real*8 deta_dz(nptsx,nptsy,nptsz),a_x(nptsx,nptsy,nptsz)
      real*8 a_y(nptsx,nptsy,nptsz),b_x(nptsx,nptsy,nptsz)
      real*8 b_y(nptsx,nptsy,nptsz),c_xy(nptsx,nptsy,nptsz)
      real*8 dax_dy(nptsx,nptsy,nptsz),dax_dz(nptsx,nptsy,nptsz)
      real*8 dx,dy,dpsi,f,db_dx(nptsx,nptsy),db_dy(nptsx,nptsy)

      real*8 a1_4,a2_3,a4_3,a5_2,a1_144,a1_18,a4_9,a5_6,a3_2,a1_12
      real*8 a7_6,a1_2,a45_12,a77_6,a107_6,a61_12,a25_12,a5_4,a1_3
      a1_4 = 1./4.
      a2_3 = 2./3.
      a4_3 = 4./3.
      a5_2 = 5./2.
      a1_144 = 1./144.
      a1_18 = 1./18.
      a4_9 = 4./9.
      a5_6 = 5./6.
      a3_2 = 3./2.
      a1_12 = 1./12.
      a7_6 = 7./6.
      a1_2 = 1./2.
      a45_12 = 45./12.
      a77_6 = 77./6.
      a107_6 = 107./6.
      a61_12 = 61./12.
      a25_12 = 25./12.
      a5_4 = 5./4.
      a1_3 = 1./3.

      
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
C           calculate gradients I know...         C
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC

C     uses 2nd order differencing

C     topo...
      do i = 1,nptsx,1
        do j = 1,nptsy,1
          if(i.eq.1)then
c     use forward difference at edge
            ds_dx(i,j)= (s(i+1,j)-s(i,j))/dx
            d2s_dx2(i,j) = ((2.*s(i,j)) - (5.*s(i+1,j)) + (4.*s(i+2,j))
     &           - (1.*s(i+3,j)))/(dx**2.)
          elseif(i.eq.nptsx)then
c     use backwards difference at far edge
            ds_dx(i,j)= (s(i,j)-s(i-1,j))/dx
           d2s_dx2(i,j) =  ((-2.*s(i,j)) + (5.*s(i-1,j)) - (4.*s(i-2,j))
     &           + (1.*s(i-3,j)))/(dx**2.)
          else
c     use centered difference in middle
           ds_dx(i,j) = (s(i+1,j) - s(i-1,j))/(2.*dx)
            d2s_dx2(i,j)= (s(i-1,j) - (2.*s(i,j)) + s(i+1,j))/(dx**2.)
          endif
          if(j.eq.1)then
            ds_dy(i,j)= (s(i,j+1) - s(i,j))/dy
            d2s_dy2(i,j) = ((2.*s(i,j)) - (5.*s(i,j+1)) + (4.*s(i,j+2))
     &           - (1.*s(i,j+3)))/(dy**2.)
          elseif(j.eq.nptsy)then
            ds_dy(i,j)= (s(i,j)-s(i,j-1))/dy
            d2s_dy2(i,j) = ((-2.*s(i,j)) + (5.*s(i,j-1)) - (4.*s(i,j-2))
     &           + (1.*s(i,j-3)))/(dy**2.)
          else
           ds_dy(i,j) = (s(i,j+1)-s(i,j-1))/(2.*dy)
            d2s_dy2(i,j)=(s(i,j-1) - (2.*s(i,j)) + s(i,j+1))/(dy**2.)
          endif

          dH_dx(i,j) = ds_dx(i,j)*(f+1.)
          dH_dy(i,j) = ds_dy(i,j)*(f+1.)

          d2H_dx2(i,j) = d2s_dx2(i,j)*(f+1.) 
          d2H_dy2(i,j) = d2s_dy2(i,j)*(f+1.)
          
c     gradients in topography of lower boundary (b - distance of base below ref 0)
          db_dx(i,j) = -ds_dx(i,j)*f
          db_dy(i,j) = -ds_dy(i,j)*f

c          write(8,*)ds_dx(i,j),dH_dx(i,j)
        enddo
      enddo
c      write(*,*) "ds_dy", ds_dy(25,1)
C     a_x, b_y, etc....
      do i = 1,nptsx,1
        do j = 1,nptsy,1
          do k = 1,nptsz,1
c     a_x corresponds to a_x in Pattyn 2003 etc.
c     zeta=(s-z)/H = s/H -((k-1)/(nptsz-1) - f/(f+1))=(nptsz-k)/(nptsz-1)
            a_x(i,j,k) = (1./H(i,j))*(ds_dx(i,j) - 
     &           (((nptsz-k)/(nptsz-1.))*dH_dx(i,j)))
            b_x(i,j,k) = (1./H(i,j))*(d2s_dx2(i,j) -
     &         (((nptsz-k)/(nptsz-1.))*(d2H_dx2(i,j))) - 
     &           (2.*a_x(i,j,k)*dH_dx(i,j)))
          
            a_y(i,j,k) = (1./H(i,j))*(ds_dy(i,j) -
     &           (((nptsz-k)/(nptsz-1.))*dH_dy(i,j)))
            b_y(i,j,k) = (1./H(i,j))*(d2s_dy2(i,j) -
     &         (((nptsz-k)/(nptsz-1.))*(d2H_dy2(i,j))) - 
     &           (2.*a_y(i,j,k)*dH_dy(i,j)))
            if(a_x(i,j,k).ne.a_x(i,j,k))then
               write(6,*)a_x(i,j,k),H(i
     $           ,j),ds_dx(i,j),dH_dx(i,j),nptsz,k
               goto 3
            endif
c            write(8,*)a_x(i,j,k),b_x(i,j,k),a_y(i,j,k),b_y(i,j,k)
          enddo
        enddo
      enddo
    

C     viscosity...
cccc currently constant
      do i = 1,nptsx,1
        do j = 1,nptsy,1
          do k = 1,nptsz,1
c     ----------- deta_dz -----------------------
c     this is actually d zeta in Pattyn notation
            if(k.eq.1)then
              deta_dz(i,j,k) = 
     &            (eta(i,j,k+1) - eta(i,j,k))/dpsi
            elseif(k.eq.nptsz)then
              deta_dz(i,j,k) = 
     &             (eta(i,j,k) - eta(i,j,k-1))/dpsi
            else
              deta_dz(i,j,k) = (eta(i,j,k+1)-eta(i,j,k-1))/(2.*dpsi)
            endif
C     ------------ deta_dx -------------------
            if(i.eq.1)then
              deta_dx(i,j,k) = 
     &           ((eta(i+1,j,k) - eta(i,j,k))/dx)
     &             + (a_x(i,j,k)*deta_dz(i,j,k))
            elseif(i.eq.nptsx)then
              deta_dx(i,j,k) = 
     &             ((eta(i,j,k) - eta(i-1,j,k))/dx)
     &             + (a_x(i,j,k)*deta_dz(i,j,k))   
            else
              deta_dx(i,j,k) = 
     &             ((eta(i+1,j,k) - eta(i-1,j,k))/(2.*dx))
     &             + (a_x(i,j,k)*deta_dz(i,j,k))
            endif

C     ---------- deta_dy -------------------
            if(j.eq.1)then
              deta_dy(i,j,k) = 
     &           ((eta(i,j+1,k) - eta(i,j,k))/dy)
     &             + (a_y(i,j,k)*deta_dz(i,j,k))
            elseif(j.eq.nptsy)then
              deta_dy(i,j,k) = 
     &           ((eta(i,j,k) - eta(i,j-1,k))/dy)
     &             + (a_y(i,j,k)*deta_dz(i,j,k))
            else
              deta_dy(i,j,k) = 
     &             ((eta(i,j+1,k) - eta(i,j-1,k))/(2.*dy))
     &             + (a_y(i,j,k)*deta_dz(i,j,k))
            endif

c            write(8,*)deta_dx(i,j,k),deta_dy(i,j,k),deta_dz(i,j,k)
          enddo
        enddo
      enddo


C     c_xy...
      do i = 1,nptsx,1
        do j = 1,nptsy,1
          do k = 1,nptsz,1
            if(j.eq.1)then
              dax_dy(i,j,k) = 
     &             (a_x(i,j+1,k) - a_x(i,j,k))/dy
            elseif(j.eq.nptsy)then
              dax_dy(i,j,k) = 
     &             (a_x(i,j,k) - a_x(i,j-1,k))/dy 
            else
              dax_dy(i,j,k) = (a_x(i,j+1,k) - a_x(i,j-1,k))/(2.*dy)
            endif
            if(k.eq.1)then
              dax_dz(i,j,k) = 
     &            (a_x(i,j,k+1) - a_x(i,j,k))/dpsi
            elseif(k.eq.nptsz)then
              dax_dz(i,j,k) = 
     &             (a_x(i,j,k) - a_x(i,j,k-1))/dpsi
            else
              dax_dz(i,j,k) = 
     &             (a_x(i,j,k+1) - a_x(i,j,k-1))/(2.*dpsi)
            endif
            c_xy(i,j,k) =  dax_dy(i,j,k) + (a_y(i,j,k)*dax_dz(i,j,k))
c            write(8,*)c_xy(i,j,k)
          enddo
        enddo
      enddo

 
 3    return
      end
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC

      subroutine acalc(nptsx,nptsy,nptsz,eta,deta_dx,deta_dy,deta_dz,
     &     a_x,a_y,b_x,b_y,c_xy,dx,dy,dpsi,NN,ds_dx,ds_dy,H,db_dx,db_dy
     &     ,ibase,aa,ir,jc,q,hmin,f,s,smax,length,kmax)
      implicit none
      integer*4 nptsx,nptsy,nptsz,NN,q,length
      real*8 eta(nptsx,nptsy,nptsz),deta_dx(nptsx,nptsy,nptsz)
      real*8 deta_dy(nptsx,nptsy,nptsz),deta_dz(nptsx,nptsy,nptsz)
      real*8 a_x(nptsx,nptsy,nptsz),a_y(nptsx,nptsy,nptsz)
      real*8 b_x(nptsx,nptsy,nptsz),b_y(nptsx,nptsy,nptsz)
      real*8 c_xy(nptsx,nptsy,nptsz),dx,dy,dpsi,ds_dx(nptsx,nptsy)
      real*8 ds_dy(nptsx,nptsy),H(nptsx,nptsy),nx,ny,hmin,smax
      real*8 db_dx(nptsx,nptsy),db_dy(nptsx,nptsy),f,s(nptsx,nptsy)
      

      real*8 a1_4,a2_3,a4_3,a5_2,a1_144,a1_18,a4_9,a5_6,a3_2,a1_12
      real*8 a7_6,a1_2,a45_12,a77_6,a107_6,a61_12,a25_12,a5_4,a1_3

      integer*4 nnz
      real*8 aa(*)
      integer*4 ir(*),jc(*)

      integer*4 i,j,k,ibase(nptsx,nptsy),kmax(nptsx,nptsy)
      a1_3 = 1./3.
      a1_4 = 1./4.
      a2_3 = 2./3.
      a4_3 = 4./3.
      a5_2 = 5./2.
      a1_144 = 1./144.
      a1_18 = 1./18.
      a4_9 = 4./9.
      a5_6 = 5./6.
      a3_2 = 3./2.
      a1_12 = 1./12.
      a7_6 = 7./6.
      a1_2 = 1./2.
      a45_12 = 45./12.
      a77_6 = 77./6.
      a107_6 = 107./6.
      a61_12 = 61./12.
      a25_12 = 25./12.
      a5_4 = 5./4.

CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
C                     Construct the matrix a                           C
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC

C     uses 2nd and 4th order differencing

      q = 1

      open(1,file='hard1.out')
      open(2,file='hard2.out')
      open(3,file='hard3.out')
      do i = 1,nptsx,1
        do j = 1,nptsy,1
          
          do k = 1,nptsz,1
c            write(6,*)i,j,k
            nx = deta_dx(i,j,k) + (a_x(i,j,k)*deta_dz(i,j,k))
            ny = deta_dy(i,j,k) + (a_y(i,j,k)*deta_dz(i,j,k))

           


 

            if(k.eq.1
     & .and.i.ne.1.and.j.ne.1.and.i.ne.nptsx.and.j.ne.nptsy)then


              if(ibase(i,j).eq.0)then !no slip base
c              eqn 1 u(i,j,k)
                 aa(q) = 1.
                 ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz+(nptsy-1)*2*nptsz)
                 jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
                 q = q+1
c              eqn 2 v(i,j,k)
                 aa(q) =  1.
                 ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz +
     &              (nptsy-1)*2*nptsz)
                 jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &                (2*nptsz + (nptsy-1)*2*nptsz)
                 q = q+1

              elseif(ibase(i,j).eq.1.and.ibase(i+1,j).ne.0.and.
     &                ibase(i,j+1).ne.0.and.ibase(i-1,j).ne.0
     &                .and.ibase(i,j-1).ne.0)then
c 151            continue
C     stress free base......
c     equation 1 u(i,j,k)
                 aa(q) = 
     &                -a3_2*((4.*a_x(i,j,k)*db_dx(i,j)) + 
     &                (a_y(i,j,k)*db_dy(i,j)) + (1./H(i,j)))/dpsi 

                 ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &                (2*nptsz+(nptsy-1)*2*nptsz)
                 jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &                (2*nptsz + (nptsy-1)*2*nptsz)
                 q = q+1
        
c     u(i+1,j,k)

                 aa(q) = a1_2*(4.*db_dx(i,j)/dx)
                 ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+
     &                (nptsy-1)*2*nptsz)
                 jc(q) = ((2*(k))-1) + (j-1)*(nptsz+nptsz)+((i+1)-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
                 q = q+1
c     u(i-1,j,k)
                 aa(q) = -a1_2*(4.*db_dx(i,j)/dx)
                 ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &                (2*nptsz+(nptsy-1)*2*nptsz)
                 jc(q) = ((2*(k))-1) + (j-1)*(nptsz+nptsz)+((i-1)-1)*
     &                (2*nptsz + (nptsy-1)*2*nptsz)
                 q = q+1

c      u(i,j+1,k)
                 aa(q) =  a1_2*db_dy(i,j)/dy 
                 ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz+(nptsy-1)*2*nptsz)
                 jc(q) = ((2*k)-1) +(j-1+1)*(nptsz+nptsz) + (i-1)*
     &                (2*nptsz + (nptsy-1)*2*nptsz)
                 q = q+1

c     u(i,j-1,k)
                 aa(q) =  -a1_2*db_dy(i,j)/dy 
                 ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+
     &                (nptsy-1)*2*nptsz)
                 jc(q) = ((2*k)-1) +(j-1-1)*(nptsz+nptsz) + (i-1)*
     &                (2*nptsz + (nptsy-1)*2*nptsz)
                 q = q+1


c     eqn 1 u(i,j,k+1)
                 aa(q) = 2.*((4.*a_x(i,j,k)*db_dx(i,j)) + 
     &                (a_y(i,j,k)*db_dy(i,j)) + (1./H(i,j)))/dpsi
                 ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz+(nptsy-1)*2*nptsz)
                 jc(q) =((2*(k+1))-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &                (2*nptsz + (nptsy-1)*2*nptsz)
                 q = q+1


c     u(i,j,k+2)
                 aa(q) = -0.5*((4.*a_x(i,j,k)*db_dx(i,j)) + 
     &                (a_y(i,j,k)*db_dy(i,j)) + (1./H(i,j)))/dpsi
                 ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &                (2*nptsz+(nptsy-1)*2*nptsz)
                 jc(q) = ((2*(k+2))-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &                (2*nptsz + (nptsy-1)*2*nptsz)
                 q = q+1



c     equation 1 v(i,j,k)
                 aa(q) = 
     &                -a3_2*((2.*a_y(i,j,k)*db_dx(i,j))+(a_x(i,j,k)*
     &                db_dy(i,j)))/dpsi 
                 ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &                (2*nptsz+(nptsy-1)*2*nptsz)
                 jc(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &                (2*nptsz + (nptsy-1)*2*nptsz)
                 q = q+1

c     v(i+1,j,k)
                 aa(q) = a1_2*db_dy(i,j)/dx 
              ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &                (2*nptsz+(nptsy-1)*2*nptsz)
              jc(q) = ((2*(k)))+(j-1)*(nptsz+nptsz)+((i+1)-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c     v(i-1,j,k)
              aa(q) = -a1_2*db_dy(i,j)/dx
              ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz+(nptsy-1)*2*nptsz)
              jc(q) = ((2*(k)))+(j-1)*(nptsz+nptsz)+(i-1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1



c     v(i,j+1,k)
c              a(((2*i)-1)+(j-1)*(nptsz+nptsz)+(k-1)*(2*nptsz+(nptsy-1)
c     &             *2*nptsz),((2*i))+(j-1+1)*(nptsz+nptsz)+(k-1)*
c     &             (2*nptsz + (nptsy-1)*2*nptsz)) =
c     &             a1_2*2.*ds_dx(i,j)/dy    
              aa(q) = a1_2*2.*db_dx(i,j)/dy 
              ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz+(nptsy-1)*2*nptsz)
              jc(q) = ((2*k))+(j-1+1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1



c    v(i,j-1,k)
              aa(q) = -a1_2*2.*db_dx(i,j)/dy  
              ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz+(nptsy-1)*2*nptsz)
              jc(q) = ((2*k))+(j-1-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1


c     v(i,j,k+1)
              aa(q) = 
     &             2.*((2.*a_y(i,j,k)*db_dx(i,j))+
     &             (a_x(i,j,k)*db_dy(i,j)))/dpsi
              ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz+(nptsy-1)*2*nptsz)
              jc(q) = ((2*(k+1)))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1

c      v(i,j,k+2)
              aa(q) = 
     &             -0.5*((2.*a_y(i,j,k)*db_dx(i,j))+
     &             (a_x(i,j,k)*db_dy(i,j)))/dpsi
              ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz+(nptsy-1)*2*nptsz)
              jc(q) = ((2*(k+2)))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1


ccc new equation - new row number
c     equation 2  u(i,j,k)
              aa(q) = 
     &             -a3_2*((2.*a_x(i,j,k)*db_dy(i,j))+
     &             (a_y(i,j,k)*db_dx(i,j)))/dpsi 
              ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1


c    eqn 2 u(i+1,j,k)
              aa(q) = a1_2*2.*db_dy(i,j)/dx
              ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*(k))-1)+(j-1)*(nptsz+nptsz) + (i+1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1

c      eqn 2 u(i-1,j,k)
              aa(q) = -a1_2*2.*db_dy(i,j)/dx 
              ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*(k))-1)+(j-1)*(nptsz+nptsz) + (i-1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1

c     eqn 2 u(i,j+1,k)
              aa(q) = a1_2*db_dx(i,j)/dy 
              ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)-1)+(j-1+1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1


c      eqn 2 u(i,j-1,k)
              aa(q) = -a1_2*db_dx(i,j)/dy 
              ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)-1)+(j-1-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1

c      eqn 2 u(i,j,k+1)
              aa(q) = 
     &             2.*((2.*a_x(i,j,k)*db_dy(i,j))+
     &             (a_y(i,j,k)*db_dx(i,j)))/dpsi  
     
              ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*(k+1))-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1

c     eqn 2 u(i,j,k+2)
              aa(q) = 
     &             -0.5*((2.*a_x(i,j,k)*db_dy(i,j))+
     &             (a_y(i,j,k)*db_dx(i,j)))/dpsi 
       
              ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*(k+2))-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1


c    eqn 2 v(i,j,k)
              aa(q) = 
     &             -a3_2*((4.*a_y(i,j,k)*db_dy(i,j)) + 
     &             (a_x(i,j,k)*db_dx(i,j))+ (1./H(i,j)))/dpsi     
c         aa(q) = 
c     &     a25_12*((4.*a_y(i,j,k)*ds_dy(i,j)) + (a_x(i,j,k)*ds_dx(i,j))
c     &             + (1./H(i,j)))/dpsi     
              ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1

c     eqn 2 v(i+1,j,k)
              aa(q) = a1_2*db_dx(i,j)/dx  
              ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*(k))) + (j-1)*(nptsz+nptsz) + (i+1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1

c      eqn 2 v(i-1,j,k)
              aa(q) = -a1_2*db_dx(i,j)/dx   
              ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*(k))) + (j-1)*(nptsz+nptsz) + (i-1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1

c      eqn 2 v(i,j+1,k)
              aa(q) = a1_2*4.*db_dy(i,j)/dy
              ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)) + (j-1+1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1

c      eqn 2 v(i,j-1,k)
              aa(q) = -a1_2*4.*db_dy(i,j)/dy 
              ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)) + (j-1-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1

c     eqn 2 v(i,j,k+1)
              aa(q) =  
     &             2.*((4.*a_y(i,j,k)*db_dy(i,j)) + 
     &             (a_x(i,j,k)*db_dx(i,j)) + (1./H(i,j)))/dpsi 
              ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*(k+1))) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1

c     eqn 2 v(i,j,k+2)
              aa(q) = 
     &             -0.5*((4.*a_y(i,j,k)*db_dy(i,j)) + 
     &             (a_x(i,j,k)*db_dx(i,j))+ (1./H(i,j)))/dpsi 
              ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*(k+2))) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
           elseif(ibase(i,j).eq.1.and.ibase(i+1,j).eq.0)then
c     u(i,j,k)
              aa(q)=-1.
              ir(q)=((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c  u(i+1,j,k)              
              aa(q)=a1_2
              ir(q)=((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + ((i+1)-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c  u(i-1,j,k)
              aa(q)=a1_2
              ir(q)=((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + ((i-1)-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c     v(i,j,k)
              aa(q)=-1.
              ir(q)=((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c  v(i+1,j,k)              
              aa(q)=a1_2
              ir(q)=((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + ((i+1)-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c  v(i-1,j,k)
              aa(q)=a1_2
              ir(q)=((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + ((i-1)-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
              elseif(ibase(i,j).eq.1.and.ibase(i-1,j).eq.0)then
c     u(i,j,k)
              aa(q)=-1.
              ir(q)=((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c  u(i+1,j,k)              
              aa(q)=a1_2
              ir(q)=((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + ((i+1)-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c  u(i-1,j,k)
              aa(q)=a1_2
              ir(q)=((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + ((i-1)-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c     v(i,j,k)
              aa(q)=-1.
              ir(q)=((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c  v(i+1,j,k)              
              aa(q)=a1_2
              ir(q)=((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + ((i+1)-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c  v(i-1,j,k)
              aa(q)=a1_2
              ir(q)=((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + ((i-1)-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
              elseif(ibase(i,j).eq.1.and.ibase(i,j+1).eq.0)then
c     u(i,j,k)
              aa(q)=-1.
              ir(q)=((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c  u(i,j+1,k)              
              aa(q)=a1_2
              ir(q)=((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)-1) + ((j+1)-1)*(nptsz+nptsz) + ((i)-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c  u(i,j-1,k)
              aa(q)=a1_2
              ir(q)=((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)-1) + ((j-1)-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c     v(i,j,k)
              aa(q)=-1.
              ir(q)=((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c  v(i,j+1,k)              
              aa(q)=a1_2
              ir(q)=((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)) + ((j+1)-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c  v(i,j-1,k)
              aa(q)=a1_2
              ir(q)=((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)) + ((j-1)-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
           elseif(ibase(i,j).eq.1.and.ibase(i,j-1).eq.0)then
c     u(i,j,k)
              aa(q)=-1.
              ir(q)=((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c  u(i,j+1,k)              
              aa(q)=a1_2
              ir(q)=((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)-1) + ((j+1)-1)*(nptsz+nptsz) + ((i)-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c  u(i,j-1,k)
              aa(q)=a1_2
              ir(q)=((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)-1) + ((j-1)-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c     v(i,j,k)
              aa(q)=-1.
              ir(q)=((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c  v(i,j+1,k)              
              aa(q)=a1_2
              ir(q)=((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)) + ((j+1)-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
c  v(i,j-1,k)
              aa(q)=a1_2
              ir(q)=((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              jc(q) = ((2*k)) + ((j-1)-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
              q = q+1
           else
c                pause '"invalid ibase"'
           endif
cc     add in other conditions on base if required
c if have a condition on thickness of base layer, less than layer thickness
c ibase check is so that this doesn't get applied for kmax =1 if base shouldn't be no slip
           elseif(kmax(i,j).le.(nptsz-2).and.k.le.kmax(i,j)
     &          .and.ibase(i,j).eq.0)then 
              
c     eqn 1 u(i,j,k)
                 aa(q) = 1.
                 ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &                (2*nptsz+(nptsy-1)*2*nptsz)
                 jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &                (2*nptsz + (nptsy-1)*2*nptsz)
                 q = q+1
c     eqn 2 v(i,j,k)
                 aa(q) = 1.
                 ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &                (2*nptsz + (nptsy-1)*2*nptsz)
                 jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &                (2*nptsz + (nptsy-1)*2*nptsz)
                 q = q+1
c if have condition on base layer which is over the whole depth let some of flow move
              elseif(kmax(i,j).gt.(nptsz-2).and.k.lt.(nptsz-2)
     &                .and.ibase(i,j).eq.0)then 

c     eqn 1 u(i,j,k)
                 aa(q) = 1.
                 ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &                (2*nptsz+(nptsy-1)*2*nptsz)
                 jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &                (2*nptsz + (nptsy-1)*2*nptsz)
                 q = q+1
c     eqn 2 v(i,j,k)
                 aa(q) = 1.
                 ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &                (2*nptsz + (nptsy-1)*2*nptsz)
                 jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &                (2*nptsz + (nptsy-1)*2*nptsz)
                 q = q+1
  
              elseif(k.eq.nptsz !)then
     &         .and.i.ne.1.and.j.ne.1.and.i.ne.nptsx.and.j.ne.nptsy)then
C     stress free top......
c     equation 1 u(i,j,k)
        aa(q) = 
     &             a3_2*((4.*a_x(i,j,k)*ds_dx(i,j)) + 
     &             (a_y(i,j,k)*ds_dy(i,j)) + (1./H(i,j)))/dpsi 
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
        jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1
        
c   eqn 1 u(i+1,j,k)
         aa(q) = a1_2*(4.*ds_dx(i,j)/dx)
         ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
         jc(q) = ((2*(k))-1) + (j-1)*(nptsz+nptsz)+(i+1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1

c     u(i-1,j,k)
         aa(q) = -a1_2*(4.*ds_dx(i,j)/dx)
         ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
         jc(q) = ((2*(k))-1) + (j-1)*(nptsz+nptsz)+(i-1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1


c     eqn 1 u(i,j+1,k)
        aa(q) =  a1_2*ds_dy(i,j)/dy 
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
        jc(q) = ((2*k)-1) +(j-1+1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c      eqn 1 u(i,j-1,k)
         aa(q) =  -a1_2*ds_dy(i,j)/dy 
         ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
         jc(q) = ((2*k)-1) +(j-1-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1

c     eqn 1 u(i,j,k-1)
        aa(q) = -2.*((4.*a_x(i,j,k)*ds_dx(i,j)) + 
     &             (a_y(i,j,k)*ds_dy(i,j)) + (1./H(i,j)))/dpsi
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
        jc(q) =((2*(k-1))-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1


c     eqn 1 u(i,j,k-2)
        aa(q) = 0.5*((4.*a_x(i,j,k)*ds_dx(i,j)) + 
     &             (a_y(i,j,k)*ds_dy(i,j)) + (1./H(i,j)))/dpsi
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
        jc(q) = ((2*(k-2))-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1


c    eqn 1 v(i,j,k)
         aa(q) = 
     & a3_2*((2.*a_y(i,j,k)*ds_dx(i,j))+(a_x(i,j,k)*ds_dy(i,j)))/dpsi 
c         aa(q) = 
c     & a25_12*((2.*a_y(i,j,k)*ds_dx(i,j))+(a_x(i,j,k)*ds_dy(i,j)))/dpsi 
         ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
         jc(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1

c    eqn 1 v(i+1,j,k)
              aa(q) = a1_2*ds_dy(i,j)/dx 
         ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
         jc(q) = ((2*(k)))+(j-1)*(nptsz+nptsz)+(i+1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1


c     eqn 1 v(i-1,j,k)
         aa(q) = -a1_2*ds_dy(i,j)/dx
         ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
         jc(q) = ((2*(k)))+(j-1)*(nptsz+nptsz)+(i-1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1


c     eqn 1 v(i,j+1,k)
         aa(q) = a1_2*2.*ds_dx(i,j)/dy 
         ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
         jc(q) = ((2*k))+(j-1+1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1


c     eqn 1 v(i,j-1,k)
         aa(q) = -a1_2*2.*ds_dx(i,j)/dy  
         ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
         jc(q) = ((2*k))+(j-1-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1


c     eqn 1 v(i,j,k-1)      
         aa(q) = 
     &  -2.*((2.*a_y(i,j,k)*ds_dx(i,j))+(a_x(i,j,k)*ds_dy(i,j)))/dpsi
c         aa(q) = 
c     &  -4.*((2.*a_y(i,j,k)*ds_dx(i,j))+(a_x(i,j,k)*ds_dy(i,j)))/dpsi
         ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
         jc(q) = ((2*(k-1)))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1

c      eqn 1 v(i,j,k-2)
          aa(q) = 
     &  0.5*((2.*a_y(i,j,k)*ds_dx(i,j))+(a_x(i,j,k)*ds_dy(i,j)))/dpsi
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*(k-2)))+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1


c     equation 2  u(i,j,k)
         aa(q) = 
     &      a3_2*((2.*a_x(i,j,k)*ds_dy(i,j))+(a_y(i,j,k)*ds_dx(i,j)))
     &             /dpsi 
         ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
         jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1


c    eqn 2 u(i+1,j,k)
          aa(q) = a1_2*2.*ds_dy(i,j)/dx
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &         *2*nptsz)
          jc(q) = ((2*(k))-1)+(j-1)*(nptsz+nptsz) + (i+1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1


c     eqn 2 u(i-1,j,k)
          aa(q) = -a1_2*2.*ds_dy(i,j)/dx 
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*(k))-1)+(j-1)*(nptsz+nptsz) + (i-1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1

c    eqn 2 u(i,j+1,k)
       aa(q) = a1_2*ds_dx(i,j)/dy 
       ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
       jc(q) = ((2*k)-1)+(j-1+1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1


c     eqn 2 u(i,j-1,k)
        aa(q) = -a1_2*ds_dx(i,j)/dy 
        ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
        jc(q) = ((2*k)-1)+(j-1-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c    eqn 2 u(i,j,k-1)
         aa(q) = 
     &      -2.*((2.*a_x(i,j,k)*ds_dy(i,j))+(a_y(i,j,k)*ds_dx(i,j)))
     &             /dpsi       
         ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
         jc(q) = ((2*(k-1))-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1

c     eqn 2 u(i,j,k-2)
        aa(q) = 
     &       0.5*((2.*a_x(i,j,k)*ds_dy(i,j))+(a_y(i,j,k)*ds_dx(i,j)))
     &             /dpsi 
         
        ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
        jc(q) = ((2*(k-2))-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c     equation 2 v(i,j,k)
         aa(q) = 
     &     a3_2*((4.*a_y(i,j,k)*ds_dy(i,j)) + (a_x(i,j,k)*ds_dx(i,j))
     &             + (1./H(i,j)))/dpsi      
         ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
         jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1

c    eqn 2 v(i+1,j,k)
        aa(q) = a1_2*ds_dx(i,j)/dx  
        ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
        jc(q) = ((2*(k))) + (j-1)*(nptsz+nptsz) + (i+1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c      eqn 2 v(i-1,j,k)
        aa(q) = -a1_2*ds_dx(i,j)/dx   
        ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
        jc(q) = ((2*(k))) + (j-1)*(nptsz+nptsz) + (i-1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c     eqn 2 v(i,j+1,k)
        aa(q) = a1_2*4.*ds_dy(i,j)/dy
        ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
        jc(q) = ((2*k)) + (j-1+1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c     eqn 2 v(i,j-1,k)
        aa(q) = -a1_2*4.*ds_dy(i,j)/dy 
        ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
        jc(q) = ((2*k)) + (j-1-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c     eqn 2 v(i,j,k-1)
         aa(q) =  
     &     -2.*((4.*a_y(i,j,k)*ds_dy(i,j)) + (a_x(i,j,k)*ds_dx(i,j))
     &             + (1./H(i,j)))/dpsi 
 
         ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
         jc(q) = ((2*(k-1))) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1

c    eqn 2 v(i,j,k-2)
         aa(q) = 
     &         0.5*((4.*a_y(i,j,k)*ds_dy(i,j)) + (a_x(i,j,k)*ds_dx(i,j))
     &             + (1./H(i,j)))/dpsi 
         ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
         jc(q) = ((2*(k-2))) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1

        elseif(j.eq.1
     &        )then
ccccccccc u=0 dv/dy=stress at j=1 (neglect transformation because small) ccccccccc
cc constant pressure  ccc
cc     eqn 1 u(i,j,k)
              aa(q) = 1.
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1

c     eqn 2 v(i,j,k)
          aa(q) = -1./dy!1.
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i,j+1,k)
          aa(q) =  1./dy
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)) + (j-1+1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1


          elseif(j.eq.nptsy)then
ccccccccc dv_dy=pressure, du_dy =0
 
c eqn 1 u(i,j,k)
          aa(q)= 1./dy
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*(k)-1)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q=q+1
c eqn 1 u(i,j-1,k)
          aa(q)= -1./dy
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*(k)-1)) + (j-1-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q=q+1


c     eqn 2 v(i,j,k)
          aa(q) = 1./dy
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &         *2*nptsz)
          jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &         (2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1
c     eqn 2 v(i,j-1,k)
          aa(q) = -1./dy
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &         *2*nptsz)
         jc(q) = ((2*k)) + (j-1-1)*(nptsz+nptsz) + (i-1)*
     &         (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1 

 

ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
       elseif(i.eq.1.and.j.le.length.and.k.ne.1.and.k.ne.nptsz)then
        
c     eqn 1 u(i,j,k)
          aa(q) = 1.         
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c (d2x+d2z)v=rho*g/eta * dys w/ vertical transformation   
c     eqn 2 v(i,j,k)
            aa(q) = (-2./(dpsi**2.))*(1./(H(i,j)**2.))+
     &         (-2./(dx**2.))
            ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
            jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
            q = q+1
c    eqn 2 v(i+1,j,k)
            aa(q) = (2./(dx**2.))
            ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
            jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i+1-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
            q = q+1
c     eqn 2 v(i,j,k-1)
            aa(q) = (1./(dpsi**2.))*(1./(H(i,j)**2.))+
     &           ((-b_x(i,j,k))/(2.*dpsi))
            ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
            jc(q) = ((2*(k-1))) + (j-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
            q = q+1
c     eqn 2 v(i,j,k+1)
            aa(q) = (1./(dpsi**2.))*(1./(H(i,j)**2.))+
     &           ((b_x(i,j,k))/(2.*dpsi))
            ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
            jc(q) = ((2*(k+1))) + (j-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
            q = q+1


            elseif(i.eq.1.and.j.gt.length.and.
     &        k.ne.1)then

c    zero dev boundary condition du_dx=0, dv_dx=0
c     eqn 1 u(i,j,k)
              aa(q) = -1./dx!-a3_2/dx
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 1 u(i+1,j,k)
              aa(q) = 1./dx!-a3_2/dx
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i+1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1

c     eqn 2 v(i,j,k)
          aa(q) =  -1./dx
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i+1,j,k)
          aa(q) =  1./dx
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*(k))) + (j-1)*(nptsz+nptsz) + (i+1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1

          elseif(i.eq.nptsx.and.k.ne.1.and.k.ne.nptsz
     &         )then

c     eqn 1 u(i,j,k)
          aa(q) = 1.         
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1

c     eqn 2 v(i,j,k)
            aa(q) = (-2./(dpsi**2.))*(1./(H(i,j)**2.))+
     &         (-2./(dx**2.))
            ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
            jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
            q = q+1
c    eqn 2 v(i-1,j,k)
            aa(q) = (2./(dx**2.))
            ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
            jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
            q = q+1
c     eqn 2 v(i,j,k-1)
            aa(q) = (1./(dpsi**2.))*(1./(H(i,j)**2.))+
     &           ((-b_x(i,j,k))/(2.*dpsi))
            ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
            jc(q) = ((2*(k-1))) + (j-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
            q = q+1
c     eqn 2 v(i,j,k+1)
            aa(q) = (1./(dpsi**2.))*(1./(H(i,j)**2.))+
     &           ((b_x(i,j,k))/(2.*dpsi))
            ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
            jc(q) = ((2*(k+1))) + (j-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
            q = q+1
       elseif(i.eq.nptsx.and.j.gt.length.and.
     &         k.ne.1)then!.and.k.ne.nptsz)then

c    pressure boundary condition du_dx=buoyancy, dv_dx=0
c     eqn 1 u(i,j,k)
              aa(q) = 1./dx!-a3_2/dx
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 1 u(i-1,j,k)
              aa(q) = -1./dx!-a3_2/dx
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1

c     eqn 2 v(i,j,k)
          aa(q) =  1./dx
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i+1,j,k)
          aa(q) =  -1./dx
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*(k))) + (j-1)*(nptsz+nptsz) + (i-1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1


ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccc k=1 i=1 start ccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
         elseif(k.eq.1
     &        .and.i.eq.1.and.j.ne.1.and.j.ne.nptsy)then


              if(ibase(i,j).eq.0)then !no slip base
c              eqn 1 u(i,j,k)
                 aa(q) = 1.
                 ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz+(nptsy-1)*2*nptsz)
                 jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
                 q = q+1
c              eqn 2 v(i,j,k)
                 aa(q) =  1.
                 ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz +
     &              (nptsy-1)*2*nptsz)
                 jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &                (2*nptsz + (nptsy-1)*2*nptsz)
                 q = q+1


   
           elseif(j.le.length)then
c     eqn 1 u(i,j,k)
          aa(q) = 1.         
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i,j,k)
          aa(q) = (-1./dx)-(a_x(i,j,k)/dpsi)         
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i+1,j,k)
          aa(q) = (1./dx)         
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i+1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i,j,k+1)
          aa(q) = (a_x(i,j,k)/dpsi)         
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k+1)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
          else
c    zero dev boundary condition du_dx=0, dv_dx=0
c     eqn 1 u(i,j,k)
              aa(q) = -1./dx!-a3_2/dx
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 1 u(i+1,j,k)
              aa(q) = 1./dx!-a3_2/dx
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i+1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1

c     eqn 2 v(i,j,k)
          aa(q) =  -1./dx
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i+1,j,k)
          aa(q) =  1./dx
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*(k))) + (j-1)*(nptsz+nptsz) + (i+1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1


           endif

  
              elseif(k.eq.nptsz !)then
     &         .and.i.eq.1.and.j.ne.1.and.j.le.length)then


c     eqn 1 u(i,j,k)
          aa(q) = 1.         
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i,j,k)
          aa(q) = (-1./dx)-(a_x(i,j,k)/dpsi)         
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i+1,j,k)
          aa(q) = (1./dx)         
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i+1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i,j,k+1)
          aa(q) = (a_x(i,j,k)/dpsi)         
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k+1)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
          elseif(k.eq.nptsz.and.i.eq.1.and.j.gt.length.and.j.ne.nptsy
     &         )then
c    pressure boundary condition du_dx=buoyancy, dv_dx=0
c     eqn 1 u(i,j,k)
              aa(q) = -1./dx!-a3_2/dx
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 1 u(i+1,j,k)
              aa(q) = 1./dx!-a3_2/dx
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i+1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1

c     eqn 2 v(i,j,k)
          aa(q) =  -1./dx
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i+1,j,k)
          aa(q) =  1./dx
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*(k))) + (j-1)*(nptsz+nptsz) + (i+1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1


          elseif(k.eq.1
     &        .and.i.eq.nptsx.and.j.ne.1.and.j.ne.nptsy)then


              if(ibase(i,j).eq.0)then !no slip base
c              eqn 1 u(i,j,k)
                 aa(q) = 1.
                 ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*
     &             (2*nptsz+(nptsy-1)*2*nptsz)
                 jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
                 q = q+1
c              eqn 2 v(i,j,k)
                 aa(q) =  1.
                 ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz +
     &              (nptsy-1)*2*nptsz)
                 jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &                (2*nptsz + (nptsy-1)*2*nptsz)
                 q = q+1



           elseif(j.le.length)then
c     eqn 1 u(i,j,k)
          aa(q) = 1.         
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i,j,k)
          aa(q) = (1./dx)-(a_x(i,j,k)/dpsi)         
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i-1,j,k)
          aa(q) = -(1./dx)         
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i,j,k+1)
         aa(q) = (a_x(i,j,k)/dpsi)         
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k+1)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
       else

c    zero dev stress du_dx=0, dv_dx=0
c     eqn 1 u(i,j,k)
              aa(q) = 1./dx!-a3_2/dx
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 1 u(i-1,j,k)
              aa(q) = -1./dx!-a3_2/dx
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1

c     eqn 2 v(i,j,k)
          aa(q) =  1./dx
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i-1,j,k)
          aa(q) =  -1./dx
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*(k))) + (j-1)*(nptsz+nptsz) + (i-1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1




c                pause '"invalid ibase"'
           endif



c     add in other conditions on base if required

  
              elseif(k.eq.nptsz !)then
     &         .and.i.eq.nptsx.and.j.ne.1.and.j.le.length)then
c     eqn 1 u(i,j,k)
          aa(q) = 1.         
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i,j,k)
          aa(q) = (1./dx)+(a_x(i,j,k)/dpsi)         
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i-1,j,k)
          aa(q) = -(1./dx)         
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i,j,k-1)
          aa(q) = -(a_x(i,j,k)/dpsi)         
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*(k-1))) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
          elseif(k.eq.nptsz.and.i.eq.nptsx.and.j.gt.length
     &         .and.j.ne.nptsy)then

c    pressure boundary condition du_dx=buoyancy, dv_dx=0
c     eqn 1 u(i,j,k)
              aa(q) = 1./dx!-a3_2/dx
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 1 u(i-1,j,k)
              aa(q) = -1./dx!-a3_2/dx
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1

c     eqn 2 v(i,j,k)
          aa(q) =  1./dx
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1
c     eqn 2 v(i-1,j,k)
          aa(q) =  -1./dx
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*(k))) + (j-1)*(nptsz+nptsz) + (i-1-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1



       else
                
C           %%%%%%%%%%%%%%%%%%%%%%% equation 1 %%%%%%%%%%%%%%%%%%%%
C           %%%%% (equal to rho*g*ds_dx)
C           %%%% u %%%%
c      u(i,j,k)
          aa(q) = 
     &             (-(8.*eta(i,j,k))/dx**2.) - (2.*eta(i,j,k)/dy**2.) - 
     &             ((2.*eta(i,j,k)/dpsi**2.)*( (4.*a_x(i,j,k)**2.) +
     &             a_y(i,j,k)**2.   + (1./H(i,j)**2.)))
          ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &             *2*nptsz)
          jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)
          q = q+1

c      u(i+1,j,k)
        aa(q) =  ((deta_dx(i,j,k) + 
     &           (a_x(i,j,k)*deta_dz(i,j,k)))*(2./dx)) + (4.*eta(i,j,k)
     &           /(dx**2.))
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k))-1) + (j-1)*(nptsz+nptsz) + (i+1-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c     u(i-1,j,k)
        aa(q) =  -((deta_dx(i,j,k) + 
     &           (a_x(i,j,k)*deta_dz(i,j,k)))*(2./dx)) + (4.*eta(i,j,k)
     &           /(dx**2.))
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k))-1) + (j-1)*(nptsz+nptsz) + (i-1-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c      u(i,j+1,k)
         aa(q) =  ((1./(2.*dy))*
     &           (deta_dy(i,j,k) + (a_y(i,j,k)*deta_dz(i,j,k)))) + 
     &           (eta(i,j,k)/dy**2.)
         ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &           *2*nptsz)
         jc(q) = ((2*k)-1) + (j-1+1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1

c      u(i,j-1,k)
        aa(q) =  -((1./(2.*dy))*
     &           (deta_dy(i,j,k) + (a_y(i,j,k)*deta_dz(i,j,k)))) + 
     &           (eta(i,j,k)/dy**2.) 
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*k)-1) + (j-1-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

            
c      u(i,j,k+1)
        aa(q) =  ((1./(2.*dpsi))*( 
     &           (4.*a_x(i,j,k)*(deta_dx(i,j,k)+(a_x(i,j,k)*
     &           deta_dz(i,j,k)))) + ( eta(i,j,k)*(4.*b_x(i,j,k) + 
     &           b_y(i,j,k)) ) + ( a_y(i,j,k)*(deta_dy(i,j,k) + 
     &           (a_y(i,j,k)*deta_dz(i,j,k)))  ) + (deta_dz(i,j,k)/
     &       H(i,j)**2.) ) )+
     &       ((eta(i,j,k)/dpsi**2.)*((4.*a_x(i,j,k)**2.)
     &           + a_y(i,j,k)**2. + (1./H(i,j)**2.) )   )
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k+1))-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

            
c     u(i,j,k-1)
       aa(q) =  -((1./(2.*dpsi))*( 
     &           (4.*a_x(i,j,k)*(deta_dx(i,j,k) + (a_x(i,j,k)*
     &           deta_dz(i,j,k)))) + ( eta(i,j,k)*(4.*b_x(i,j,k) + 
     &           b_y(i,j,k)) ) + ( a_y(i,j,k)*(deta_dy(i,j,k) + 
     &           (a_y(i,j,k)*deta_dz(i,j,k)))  ) + (deta_dz(i,j,k)/
     &           H(i,j)**2.) ) ) +  (  (eta(i,j,k)/dpsi**2.)*( 
     &        (4.*a_x(i,j,k)**2.) + a_y(i,j,k)**2. + (1./H(i,j)**2.) ) )
       ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*(k-1))-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1

c      u(i+1,j,k+1)
        aa(q) =  (8.*a_x(i,j,k)*
     &           eta(i,j,k))/(4.*dx*dpsi)
        ir(q) =((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k+1))-1) + (j-1)*(nptsz+nptsz) + (i-1+1)
     &           *(2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c    u(i+1,j,k-1)
        aa(q) =  -(8.*a_x(i,j,k)*
     &           eta(i,j,k))/(4.*dx*dpsi) 
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k-1))-1) + (j-1)*(nptsz+nptsz) +(i+1-1)
     &           *(2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c     u(i-1,j,k+1)
         aa(q) =  -(8.*a_x(i,j,k)*
     &           eta(i,j,k))/(4.*dx*dpsi)
         ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz +(nptsy-1)
     &           *2*nptsz)
         jc(q) = ((2*(k+1))-1) + (j-1)*(nptsz+nptsz) + (i-1-1)
     &           *(2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1
c     u(i-1,j,k-1)
       aa(q) =  (8.*a_x(i,j,k)*
     &           eta(i,j,k))/(4.*dx*dpsi) 
       ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*(k-1))-1) + (j-1)*(nptsz+nptsz) + (i-1-1)
     &           *(2*nptsz + (nptsy-1)*2*nptsz)
       q =q+1
c      u(i,j+1,k+1)
        aa(q) =  (a_y(i,j,k)*
     &           eta(i,j,k))/(2.*dy*dpsi) 
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k+1))-1) + (j-1+1)*(nptsz+nptsz) + (i-1)
     &           *(2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c      u(i,j-1,k+1)
        aa(q) =  -(a_y(i,j,k)*
     &           eta(i,j,k))/(2.*dy*dpsi) 
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k+1))-1) + (j-1-1)*(nptsz+nptsz) + (i-1)
     &           *(2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c     u(i,j+1,k-1)
        aa(q) =  -(a_y(i,j,k)*
     &           eta(i,j,k))/(2.*dy*dpsi) 
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k-1))-1) + (j-1+1)*(nptsz+nptsz) + (i-1)
     &           *(2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c    u(i,j-1,k-1)
        aa(q) =  (a_y(i,j,k)*
     &           eta(i,j,k))/(2.*dy*dpsi) 
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k-1))-1) + (j-1-1)*(nptsz+nptsz) + (i-1)
     &           *(2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1
            
            
C           %%%% v %%%%
c  v(i,j,k)
         aa(q) =  -(6.*a_x(i,j,k)*
     &           a_y(i,j,k)*eta(i,j,k))/dpsi**2. 
         ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &           *2*nptsz)
         jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
         q =q +1

c      v(i+1,j,k)
        aa(q) =  (deta_dy(i,j,k) + 
     &        (a_y(i,j,k)*deta_dz(i,j,k)))/(2.*dx)
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k))) + (j-1)*(nptsz+nptsz) + (i+1-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c      v(i-1,j,k)
        aa(q) =  -(deta_dy(i,j,k) + 
     &           (a_y(i,j,k)*deta_dz(i,j,k)))/(2.*dx)
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k))) + (j-1)*(nptsz+nptsz) + (i-1-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c     v(i,j+1,k)
        aa(q) =  (deta_dx(i,j,k) + 
     &           (a_x(i,j,k)*deta_dz(i,j,k)))/dy 
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*k))+(j-1+1)*(nptsz+nptsz)+(i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1


c     v(i,j-1,k)
        aa(q)=  -(deta_dx(i,j,k) + 
     &           (a_x(i,j,k)*deta_dz(i,j,k)))/dy 
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*k)) + (j-1-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1
c    v(i,j,k+1)
       aa(q) =  (( (2.*a_y(i,j,k)*
     &           (deta_dx(i,j,k) + a_x(i,j,k)*deta_dz(i,j,k))) + 
     &           (a_x(i,j,k)*(deta_dy(i,j,k) + a_y(i,j,k)*
     &         deta_dz(i,j,k)))+
     &       (3.*c_xy(i,j,k)*eta(i,j,k)))/(2.*dpsi))
     &           + ((3.*a_x(i,j,k)*a_y(i,j,k)*eta(i,j,k))/dpsi**2.)
       ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &      *2*nptsz)
       jc(q) = ((2*(k+1))) + (j-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1
c     v(i,j,k-1)
        aa(q) =  -(( (2.*a_y(i,j,k)*
     &           (deta_dx(i,j,k) + a_x(i,j,k)*deta_dz(i,j,k))) + 
     &           (a_x(i,j,k)*(deta_dy(i,j,k) + a_y(i,j,k)*
     &          deta_dz(i,j,k)))+
     &      (3.*c_xy(i,j,k)*eta(i,j,k)))/(2.*dpsi))
     &           + ((3.*a_x(i,j,k)*a_y(i,j,k)*eta(i,j,k))/dpsi**2.)
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k-1))) + (j-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1
c    v(i+1,j+1,k)
        aa(q) = (3.*eta(i,j,k))
     &           /(4.*dx*dy)
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k))) + (j-1+1)*(nptsz+nptsz) + 
     &           (i+1-1)*(2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c    v(i-1,j-1,k)
        aa(q) = (3.*eta(i,j,k))/
     &           (4.*dx*dy) 
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k))) + (j-1-1)*(nptsz+nptsz) + (i-1-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c      v(i+1,j-1,k)
       aa(q) =  -(3.*eta(i,j,k))/
     &           (4.*dx*dy) 
       ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*(k))) + (j-1-1)*(nptsz+nptsz) + (i+1-1)
     &           *(2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1

c     v(i-1,j+1,k)
        aa(q) =  -(3.*eta(i,j,k))/
     &           (4.*dx*dy)
        ir(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz+(nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k))) + (j-1+1)*(nptsz+nptsz) + (i-1-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1    

c   v(i+1,j,k+1)
        aa(q) = (3.*a_y(i,j,k)*
     &           eta(i,j,k))/(4.*dx*dpsi)
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q)= ((2*(k+1))) + (j-1)*(nptsz+nptsz) + (i-1+1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c     v(i-1,j,k+1)
       aa(q) =  -(3.*a_y(i,j,k)*
     &           eta(i,j,k))/(4.*dx*dpsi) 
       ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q)= ((2*(k+1))) + (j-1)*(nptsz+nptsz) + (i-1-1)
     &           *(2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1
c     v(i+1,j,k-1)
        aa(q)=  -(3.*a_y(i,j,k)*
     &           eta(i,j,k))/(4.*dx*dpsi) 
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k-1))) + (j-1)*(nptsz+nptsz) + (i+1-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1
c     v(i-1,j,k-1)
        aa(q) =  (3.*a_y(i,j,k)*
     &           eta(i,j,k))/(4.*dx*dpsi) 
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k-1))) + (j-1)*(nptsz+nptsz) + (i-1-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1
c      v(i,j+1,k+1)
       aa(q) =  (3.*a_x(i,j,k)*
     &           eta(i,j,k))/(4.*dy*dpsi)  
       ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*(k+1))) + (j-1+1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1

c     v(i,j-1,k+1)
        aa(q) =  -(3.*a_x(i,j,k)*
     &           eta(i,j,k))/(4.*dy*dpsi)
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k+1))) + (j-1-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1
            
c    v(i,j+1,k-1)
        aa(q) =  -(3.*a_x(i,j,k)*
     &           eta(i,j,k))/(4.*dy*dpsi)  
        ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k-1))) + (j-1+1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c     v(i,j-1,k-1)
       aa(q) =  (3.*a_x(i,j,k)*
     &           eta(i,j,k))/(4.*dy*dpsi) 
       ir(q) = ((2*k)-1)+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*(k-1))) + (j-1-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1
            
C            %%%%%%%%%%%%%%%%%%%%%%%% end equation 1 %%%%%%%%%%%%%%%%%%%%%%%%
            
C            %%%%%%%%%%%%%%%%%%%%%%%%%%%%% equation 2 %%%%%%%%%%%%%%%%%%%%%%
C            %%%%% (equal to rho*g*ds_dy)
C            %%%% u %%%%
c     u(i,j,k)
         aa(q) =   -(6.*a_y(i,j,k)*
     &           a_x(i,j,k)*eta(i,j,k))/dpsi**2. 
         ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
         jc(q) = ((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1

c     u(i+1,j,k)
        aa(q) =   (deta_dy(i,j,k) + 
     &           (a_y(i,j,k)*deta_dz(i,j,k)))/dx
        ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k))-1) + (j-1)*(nptsz+nptsz) + (i+1-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1


c     u(i-1,j,k)
        aa(q) =  -(deta_dy(i,j,k) + 
     &           (a_y(i,j,k)*deta_dz(i,j,k)))/dx
        ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k))-1) + (j-1)*(nptsz+nptsz) + (i-1-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c     u(i,j+1,k)
       aa(q) =  (deta_dx(i,j,k) + 
     &           (a_x(i,j,k)*deta_dz(i,j,k)))/(2.*dy)
       ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*k)-1) + (j-1+1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1

c      u(i,j-1,k)
       aa(q) =  -(deta_dx(i,j,k) + 
     &           (a_x(i,j,k)*deta_dz(i,j,k)))/(2.*dy)
       ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*k)-1) + (j-1-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1
c     u(i,j,k+1)
       aa(q) =  (( (2.*a_x(i,j,k)*
     &           (deta_dy(i,j,k) + a_y(i,j,k)*deta_dz(i,j,k))) + 
     &           (a_y(i,j,k)*(deta_dx(i,j,k) + a_x(i,j,k)*
     &          deta_dz(i,j,k)))+
     &      (3.*c_xy(i,j,k)*eta(i,j,k)))/(2.*dpsi))
     &           + ((3.*a_y(i,j,k)*a_x(i,j,k)*eta(i,j,k))/dpsi**2.)
       ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*(k+1))-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1
c     u(i,j,k-1)
        aa(q) =  -(( (2.*a_x(i,j,k)*
     &           (deta_dy(i,j,k) + a_y(i,j,k)*deta_dz(i,j,k))) + 
     &           (a_y(i,j,k)*(deta_dx(i,j,k) + a_x(i,j,k)*
     &          deta_dz(i,j,k)))+
     &      (3.*c_xy(i,j,k)*eta(i,j,k)))/(2.*dpsi))
     &           + ((3.*a_y(i,j,k)*a_x(i,j,k)*eta(i,j,k))/dpsi**2.)
        ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k-1))-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1
c     u(i+1,j+1,k)
       aa(q) =  (3.*eta(i,j,k))/
     &           (4.*dx*dy)
       ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*(k))-1) + (j-1+1)*(nptsz+nptsz) + (i+1-1)
     &           *(2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1

c     u(i-1,j-1,k)
        aa(q) =   (3.*eta(i,j,k))/
     &           (4.*dx*dy)
        ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k))-1) + (j-1-1)*(nptsz+nptsz) + (i-1-1)
     &           *(2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c     u(i+1,j-1,k)
       aa(q) =  -(3.*eta(i,j,k))/
     &           (4.*dx*dy)
       ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*(k))-1) + (j-1-1)*(nptsz+nptsz) + (i+1-1)
     &           *(2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1

c     u(i-1,j+1,k)
        aa(q) =   -(3.*eta(i,j,k))/
     &           (4.*dx*dy)
        ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k))-1) + (j-1+1)*(nptsz+nptsz) + (i-1-1)
     &           *(2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1           


c    u(i+1,j,k+1)
        aa(q) =  (3.*a_y(i,j,k)*
     &           eta(i,j,k))/(4.*dx*dpsi)
        ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k+1))-1) + (j-1)*(nptsz+nptsz) + (i-1+1)
     &           *(2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c     u(i-1,j,k+1)
         aa(q) =  -(3.*a_y(i,j,k)*
     &           eta(i,j,k))/(4.*dx*dpsi)
         ir(q)= ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
         jc(q) = ((2*(k+1))-1) + (j-1)*(nptsz+nptsz) + (i-1-1)
     &           *(2*nptsz + (nptsy-1)*2*nptsz)
         q = q+1

c   u(i+1,j,k-1)
        aa(q) =  -(3.*a_y(i,j,k)*
     &           eta(i,j,k))/(4.*dx*dpsi)
        ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k-1))-1) + (j-1)*(nptsz+nptsz) + (i+1-1)
     &           *(2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1
c      u(i-1,j,k-1)
       aa(q) =  (3.*a_y(i,j,k)*
     &           eta(i,j,k))/(4.*dx*dpsi)
       ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*(k-1))-1) + (j-1)*(nptsz+nptsz) + (i-1-1)
     &           *(2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1
c   u(i,j+1,k+1)
       aa(q) =   (3.*a_x(i,j,k)*
     &           eta(i,j,k))/(4.*dy*dpsi)
       ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*(k+1))-1) + (j-1+1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1

c     u(i,j-1,k+1)
            aa(q) =   -(3.*a_x(i,j,k)*
     &           eta(i,j,k))/(4.*dy*dpsi)
          ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
            jc(q) = ((2*(k+1))-1) + (j-1-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
            q = q+1
            
c    u(i,j+1,k-1)
        aa(q)=   -(3.*a_x(i,j,k)*
     &           eta(i,j,k))/(4.*dy*dpsi)
        ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k-1))-1) + (j-1+1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c    u(i,j-1,k-1)
        aa(q) =   (3.*a_x(i,j,k)*
     &           eta(i,j,k))/(4.*dy*dpsi)
        ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k-1))-1) + (j-1-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1
            


C            %%%% v %%%%
c     v(i,j,k)
       aa(q) = (-(8.*eta(i,j,k))/dy**2.)
     &           - (2.*eta(i,j,k)/dx**2.) - 
     &  ((2.*eta(i,j,k)/dpsi**2.)*( 
     &          (4.*a_y(i,j,k)**2.) + a_x(i,j,k)**2. + (1./H(i,j)**2.)))
       ir(q)= ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &          (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1

c     v(i+1,j,k)
       aa(q) =  ((1./(2.*dx))*(
     &           deta_dx(i,j,k) + (a_x(i,j,k)*deta_dz(i,j,k)))) + 
     &           (eta(i,j,k)/dx**2.) 
       ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q)= ((2*(k))) + (j-1)*(nptsz+nptsz) + (i+1-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1

c      v(i-1,j,k)
        aa(q) =   -((1./(2.*dx))*(
     &           deta_dx(i,j,k) + (a_x(i,j,k)*deta_dz(i,j,k)))) + 
     &           (eta(i,j,k)/dx**2.) 
        ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k))) + (j-1)*(nptsz+nptsz) + (i-1-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c      v(i,j+1,k)
       aa(q)=  ((deta_dy(i,j,k) + 
     &           (a_y(i,j,k)*deta_dz(i,j,k)))*(2./dy)) + (4.*eta(i,j,k)
     &           /(dy**2.))
       ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*k)) + (j-1+1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1

c     v(i,j-1,k)
        aa(q)=   -((deta_dy(i,j,k) +
     &           (a_y(i,j,k)*deta_dz(i,j,k)))*(2./dy)) + (4.*eta(i,j,k)/
     &           (dy**2.))
        ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*k)) + (j-1-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1
            
c     v(i,j,k+1)
       aa(q) =   ((1./(2.*dpsi))*( 
     &           (4.*a_y(i,j,k)*(deta_dy(i,j,k) + (a_y(i,j,k)*
     &           deta_dz(i,j,k)))) + ( eta(i,j,k)*(4.*b_y(i,j,k) + 
     &           b_x(i,j,k)) ) + ( a_x(i,j,k)*(deta_dx(i,j,k) + 
     &           (a_x(i,j,k)*deta_dz(i,j,k)))  ) + (deta_dz(i,j,k)/
     &           H(i,j)**2.) ) ) +  (  (eta(i,j,k)/dpsi**2.)*( 
     &         (4.*a_y(i,j,k)**2.) + a_x(i,j,k)**2. + (1./H(i,j)**2.)))
       ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*(k+1))) + (j-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1
c       v(i,j,k-1)
       aa(q) =  -((1./(2.*dpsi))*
     &           ( (4.*a_y(i,j,k)*(deta_dy(i,j,k) + (a_y(i,j,k)*
     &           deta_dz(i,j,k)))) + ( eta(i,j,k)*(4.*b_y(i,j,k) + 
     &           b_x(i,j,k)) ) + ( a_x(i,j,k)*(deta_dx(i,j,k) + 
     &           (a_x(i,j,k)*deta_dz(i,j,k)))  ) + (deta_dz(i,j,k)/
     &           H(i,j)**2.) ) ) +  (  (eta(i,j,k)/dpsi**2.)*( 
     &         (4.*a_y(i,j,k)**2.) + a_x(i,j,k)**2. + (1./H(i,j)**2.)))
       ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*(k-1))) + (j-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1
c      v(i+1,j,k+1)
       aa(q) =   (a_x(i,j,k)*
     &           eta(i,j,k))/(2.*dx*dpsi)
       ir(q)= ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*(k+1))) + (j-1)*(nptsz+nptsz) + (i-1+1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1

c      v(i-1,j,k+1)
       aa(q) =    -(a_x(i,j,k)*
     &           eta(i,j,k))/(2.*dx*dpsi)
       ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*(k+1))) + (j-1)*(nptsz+nptsz) + (i-1-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1
c    v(i+1,j,k-1)
        aa(q) =   -(a_x(i,j,k)*
     &           eta(i,j,k))/(2.*dx*dpsi)
        ir(q)= ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k-1))) + (j-1)*(nptsz+nptsz) + (i+1-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

c      v(i-1,j,k-1)
       aa(q) =   (a_x(i,j,k)*
     &           eta(i,j,k))/(2.*dx*dpsi)
       ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*(k-1))) + (j-1)*(nptsz+nptsz) + (i-1-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1
c      v(i,j+1,k+1)
       aa(q) =  (8.*a_y(i,j,k)*
     &           eta(i,j,k))/(4.*dy*dpsi) 
       ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*(k+1))) + (j-1+1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1

c      v(i,j-1,k+1)
       aa(q) =  -(8.*a_y(i,j,k)*
     &           eta(i,j,k))/(4.*dy*dpsi)
       ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*(k+1))) + (j-1-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1
            
c    v(i,j+1,k-1)
       aa(q) =  -(8.*a_y(i,j,k)*
     &           eta(i,j,k))/(4.*dy*dpsi) 
       ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
       jc(q) = ((2*(k-1))) + (j-1+1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
       q = q+1

c     v(i,j-1,k-1)
        aa(q)=   (8.*a_y(i,j,k)*
     &           eta(i,j,k))/(4.*dy*dpsi)
        ir(q) = ((2*k))+(j-1)*(nptsz+nptsz)+(i-1)*(2*nptsz + (nptsy-1)
     &           *2*nptsz)
        jc(q) = ((2*(k-1))) + (j-1-1)*(nptsz+nptsz) + (i-1)*
     &           (2*nptsz + (nptsy-1)*2*nptsz)
        q = q+1

C            %%%%%%%%%%%%%%%%%%%%%% end equation 2 %%%%%%%%%%%%%%%%%%%%%%%%%%

c            endif
c            goto 111
c            else
        endif
 333    continue
c 111        continue
          enddo
        enddo
      enddo

      q = q-1
      close(1)
      close(2)
      close(3)
      return
      end
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC

ccccccccccccc
      subroutine bcalc(b,nptsx,nptsy,nptsz,rho,g,ds_dx,ds_dy,NN,f,
     &     H,s,hmin,eta,uold,vold,q,ibase,
     &     smax,length,kmax)
      implicit none
      integer*4 nptsx,nptsy,nptsz,NN,q,length,ibase(nptsx,nptsy)
      real*8 b(NN),rho,g,ds_dx(nptsx,nptsy),ds_dy(nptsx,nptsy),f
      real*8 H(nptsx,nptsy),s(nptsx,nptsy),hmin,vmax,tar_x,tar_y
      real*8 eta(nptsx,nptsy,nptsz),uold(nptsx,nptsy,nptsz)
      real*8 vold(nptsx,nptsy,nptsz),maxv,smax,dpsi,smin
      integer*4 i,j,k,kmax(nptsx,nptsy)

CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
C                        create RHS vector b                                   C
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
      smin=hmin/(1.+f)
      
      dpsi = 1./(nptsz-1.)

      do i = 1,nptsx,1
        do j = 1,nptsy,1
          do k = 1,nptsz,1

             if(k.eq.1
     &     .and.i.ne.1.and.j.ne.1.and.j.ne.nptsy.and.i.ne.nptsx)then
                if(ibase(i,j).eq.0)then
                   b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                   b(((k*2)) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                elseif(ibase(i,j).eq.1.and.ibase(i+1,j).ne.0
     &                  .and.ibase(i-1,j).ne.0.and.ibase(i,j+1)
     &                  .ne.0.and.ibase(i,j-1).ne.0)then
                   b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                   b(((k*2)) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                elseif(ibase(i,j).eq.1.and.ibase(i+1,j).eq.0)then
                   b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                   b(((k*2)) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                elseif(ibase(i,j).eq.1.and.ibase(i-1,j).eq.0)then
                   b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                   b(((k*2)) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                elseif(ibase(i,j).eq.1.and.ibase(i,j+1).eq.0)then
                   b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                   b(((k*2)) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                elseif(ibase(i,j).eq.1.and.ibase(i,j-1).eq.0)then
                   b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                   b(((k*2)) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                endif
             elseif(kmax(i,j).le.(nptsz-2).and.k.le.kmax(i,j)
     &               .and.ibase(i,j).eq.0)then
                b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &               (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                b(((2*k)) + (j-1)*(nptsz+nptsz) + 
     &               (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
             elseif(kmax(i,j).gt.(nptsz-2).and.k.lt.(nptsz-2)
     &               .and.ibase(i,j).eq.0)then
                b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &               (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                b(((2*k)) + (j-1)*(nptsz+nptsz) + 
     &               (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
             elseif(k.eq.nptsz.and.i.ne.1.and.j.ne.1.and.i.ne.nptsx.and.
     &           j.ne.nptsy)then
                b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &             (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                b(((2*k)) + (j-1)*(nptsz+nptsz) + 
     &               (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.


ccccc j conditions 
             elseif(j.eq.1)then
               
                  b(((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                  b(((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &               (2*nptsz + (nptsy-1)*2*nptsz)) = 0.

cccccc simple
               elseif(j.eq.nptsy)then
                     b(((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*(2*nptsz+
     $                 (nptsy-1)*2*nptsz)) = 0.
                  b(((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*(2*nptsz +
     $                 (nptsy-1)*2*nptsz)) = 0.
cccc i conditions
             elseif(i.eq.1.and.j.le.length.and.k.ne.1.and.k.ne.nptsz
     &               )then
                  b(((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*(2*nptsz +
     $                 (nptsy-1)*2*nptsz)) = 0.
                  b(((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*(2*nptsz +
     $                 (nptsy-1)*2*nptsz)) = 
     &                 rho*g*ds_dy(i,j)/(eta(i,j,k))
             elseif(i.eq.1.and.k.ne.1.and.j.gt.length
     &               )then
                  b(((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*(2*nptsz +
     $                 (nptsy-1)*2*nptsz)) = 0.
                  b(((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*(2*nptsz +
     $                 (nptsy-1)*2*nptsz)) = 0.
c             
               elseif(i.eq.nptsx.and.j.le.length.and.
     &                 k.ne.1.and.k.ne.nptsz)then
                  b(((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*(2*nptsz +
     $                 (nptsy-1)*2*nptsz)) =0.
                  b(((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*(2*nptsz +
     $                 (nptsy-1)*2*nptsz)) = 
     &                 rho*g*ds_dy(i,j)/(eta(i,j,k))
               elseif(i.eq.nptsx.and.k.ne.1.and.j.gt.length)then
                  b(((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*(2*nptsz +
     $                 (nptsy-1)*2*nptsz)) = 0.
                  b(((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*(2*nptsz +
     $                 (nptsy-1)*2*nptsz)) = 0.
                 elseif(k.eq.1
     &               .and.i.eq.1.and.j.ne.1.and.j.ne.nptsy)then
                if(ibase(i,j).eq.0)then
                   b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                   b(((k*2)) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                   elseif(j.le.length)then
                   b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
     &             
                   b(((k*2)) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                   else
                   b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
             
                   b(((k*2)) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.

                endif
                elseif(k.eq.nptsz.and.i.eq.1.and.j.ne.1.and.
     &           j.le.length)then
                b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &             (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                b(((2*k)) + (j-1)*(nptsz+nptsz) + 
     &               (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
             elseif(k.eq.nptsz.and.i.eq.1.and.j.ne.nptsy.and.
     &           j.gt.length)then
                b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &             (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                b(((2*k)) + (j-1)*(nptsz+nptsz) + 
     &               (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) =  0.  

 
             elseif(k.eq.1
     &               .and.i.eq.nptsx.and.j.ne.1.and.j.ne.nptsy)then
                if(ibase(i,j).eq.0)then
                   b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                   b(((k*2)) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                elseif(j.le.length)then
                   b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 
     &             0.
                   b(((k*2)) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                   else
                   b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0. 
                   b(((k*2)) + (j-1)*(nptsz+nptsz) + 
     &                  (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                endif
             elseif(k.eq.nptsz.and.i.eq.nptsx.and.j.le.length.and.
     &           j.ne.1)then
                b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &             (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                b(((2*k)) + (j-1)*(nptsz+nptsz) + 
     &               (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
             elseif(k.eq.nptsz.and.i.eq.nptsx.and.j.gt.length.and.
     &           j.ne.nptsy)then
                b(((2*k)-1) + (j-1)*(nptsz+nptsz) + 
     &             (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
                b(((2*k)) + (j-1)*(nptsz+nptsz) + 
     &               (i-1)*(2*nptsz + (nptsy-1)*2*nptsz)) = 0.
 
            else
                b(((2*k)-1) + (j-1)*(nptsz+nptsz) + (i-1)*
     &             (2*nptsz + (nptsy-1)*2*nptsz)) = rho*g*ds_dx(i,j)
                b(((2*k)) + (j-1)*(nptsz+nptsz) + (i-1)*
     &               (2*nptsz + (nptsy-1)*2*nptsz)) = rho*g*ds_dy(i,j)
            endif
            
 111        continue

          enddo
        enddo
      enddo
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC

      return
      end
ccccccccccccc


CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC

      subroutine topow(nptsx,nptsy,nptsz,u,v,w,dx,dy,dpsi,dt,s,H,f,
     &     dH_dt,a_x,a_y,ds_dx,ds_dy,dH_dx,dH_dy,hmin,
     &     hinit,number,length,height,ierr,ibase,icount)
      implicit none
      integer*4 nptsx,nptsy,nptsz,i,k,j,tmp,number,length,nnz
      integer*4 itol,itmax,iter,nrow,ierr,ibase(nptsx,nptsy),icount(4)
      integer*4 maxits,iout,im,lfil,job
      integer*4 , ALLOCATABLE :: ir(:),jc(:),jao(:),iao(:),jlu(:),
     &     ju(:),jw(:)
      real*8 u(nptsx,nptsy,nptsz),utmp(nptsx,nptsy,nptsz)
      real*8 w(nptsx,nptsy,nptsz),a_x(nptsx,nptsy,nptsz),hrun
      real*8 s(nptsx,nptsy),H(nptsx,nptsy),dy
      real*8 dx,dpsi,dt,f,dH_dt(nptsx,nptsy),wmax,hmin,height
      real*8 v(nptsx,nptsy,nptsz),a_y(nptsx,nptsy,nptsz)

      real*8 du_dx(nptsx,nptsy,nptsz),dv_dy(nptsx,nptsy,nptsz)
      real*8 uav(nptsx,nptsy),vav(nptsx,nptsy)
      real*8 uav_x(nptsx,nptsy),stmp(nptsx,nptsy)
      real*8 u_psi(nptsx,nptsy,nptsz),v_psi(nptsx,nptsy,nptsz)
      real*8 ds_dx(nptsx,nptsy),ds_dy(nptsx,nptsy)
      real*8 coravx(nptsx,nptsy),maxx,maxy
      real*8 Difx(nptsx,nptsy),Dify(nptsx,nptsy)
      real*8 dH_dx(nptsx,nptsy),dH_dta(nptsx,nptsy),dH_dy(nptsx,nptsy)
      real*8 aai(max(nptsx,nptsy)),bbi(max(nptsx,nptsy))
      real*8 cci(max(nptsx,nptsy)),rri(max(nptsx,nptsy))
      real*8 uui(max(nptsx,nptsy)),maxv,vmax,hinit,hav
      real*8 tol,er,H_old(nptsx,nptsy)
      real*8 Difx_n(nptsx,nptsy),Dify_n(nptsx,nptsy)
      real*8 droptol,eps
      real*8 , ALLOCATABLE :: aao(:),uu(:),aa(:),rr(:),bb(:),a(:),c(:),
     &     alu(:),ww(:),scaletmp(:)


      do i = 1,nptsx,1
        do j = 1,nptsy,1
          do k = 1,nptsz,1
            if(k.eq.1)then
              u_psi(i,j,k) = (u(i,j,k+1) - u(i,j,k))/dpsi
              v_psi(i,j,k) = (v(i,j,k+1) - v(i,j,k))/dpsi
            elseif(k.eq.nptsz)then
c     else
              u_psi(i,j,k) = (u(i,j,k) - u(i,j,k-1))/dpsi
              v_psi(i,j,k) = (v(i,j,k) - v(i,j,k-1))/dpsi
            else
              u_psi(i,j,k) = (u(i,j,k+1) - u(i,j,k-1))/(2.*dpsi)
              v_psi(i,j,k) = (v(i,j,k+1) - v(i,j,k-1))/(2.*dpsi)
            endif
          enddo
        enddo
      enddo
c      write(*,*) "u_psi",u_psi(25,1,nptsz),"v_psi",v_psi(25,1,nptsz)
      do i = 1,nptsx,1
        do j = 1,nptsy,1
          do k = 1,nptsz,1
            if(i.eq.1)then
              du_dx(i,j,k) = ((u(i+1,j,k) - u(i,j,k))/dx)
     &             - (a_x(i,j,k)*u_psi(i,j,k)) 
c -ve a*du/dzeta term because zeta runs from 0 at top of model to 1 at base
c so u_psi = -du_dzeta
            elseif(i.eq.nptsx)then
              du_dx(i,j,k) = ((u(i,j,k) - u(i-1,j,k))/dx)
     &             - (a_x(i,j,k)*u_psi(i,j,k))
            else
c     du_dx(i,k) = ((u(i+1,k) - u(i-1,k))/(2.*dx))
              du_dx(i,j,k) = ((u(i+1,j,k) - u(i-1,j,k))/(2.*dx))
     &             - (a_x(i,j,k)*u_psi(i,j,k))
            endif
            if(j.eq.1)then
              dv_dy(i,j,k) = ((v(i,j+1,k) - v(i,j,k))/dy)
     &             - (a_y(i,j,k)*v_psi(i,j,k)) ! -ve because sign of v_psi
            elseif(j.eq.nptsy)then
              dv_dy(i,j,k) = ((v(i,j,k) - v(i,j-1,k))/dy)
     &             - (a_y(i,j,k)*v_psi(i,j,k))
            else
c     du_dx(i,k) = ((u(i+1,k) - u(i-1,k))/(2.*dx))
              dv_dy(i,j,k) = ((v(i,j+1,k) - v(i,j-1,k))/(2.*dy))
     &             - (a_y(i,j,k)*v_psi(i,j,k))
c              dv_dy(i,j,k) = ((v(i,j+1,k) - v(i,j,k))/(1.*dy))
c     &             - (a_y(i,j,k)*v_psi(i,j,k))
c              dv_dy(i,j,k) = ((v(i,j,k) - v(i,j-1,k))/(1.*dy))
c     &             - (a_y(i,j,k)*v_psi(i,j,k))
            endif
          enddo
        enddo
      enddo
c      write(*,*) "dv_dy",dv_dy(25,1,nptsz)     
      do i = 1,nptsx,1
        do j = 1,nptsy,1
          do k = 1,nptsz,1
            if(k.eq.1)then
c     no vertical velocity of material on base
c (doesn't mean base position can't change)
              w(i,j,k) = 0.
           else
              w(i,j,k) = w(i,j,k-1) -
     &             (du_dx(i,j,k)+dv_dy(i,j,k))*H(i,j)*dpsi
c              w(i,j,k) = w(i,j,k-1) -
c     &             (dv_dy(i,j,k))*H(i,j)*dpsi
            endif
          enddo
        enddo
      enddo

           nrow = nptsy*nptsx
           nnz=nptsx*2+2*(length-1)*4+(nptsy-length-1)*2
     &           +(nptsx-2)*(nptsy-2)*5
           allocate(aa(nnz),ir(nnz),jc(nnz),rr(nrow),
     &          aao(nnz),jao(nnz),iao(nrow+1),
     &      uu(nrow),scaletmp(nrow),bb(nrow),a(nrow),c(nrow),
     &            alu(nrow*nrow),jlu(nrow*nrow),ww(nrow+1),
     &            jw(2*nrow),ju(nrow))
           write(6,*) "nnz",nnz

c calculate diffusivities
           do i = 1,nptsx,1
              do j = 1,nptsy,1
                 uav(i,j) = 0.
                 vav(i,j) = 0.
                 dH_dt(i,j) = 0.
              enddo
           enddo
           
           do i = 1,nptsx,1
              do j = 1,nptsy,1
                 do k = 1,nptsz,1
                    if(k.eq.1.or.k.eq.nptsz)then
                       uav(i,j) = uav(i,j) + (u(i,j,k)*0.5)
                       vav(i,j) = vav(i,j) + (v(i,j,k)*0.5)
                    else
                       uav(i,j) = uav(i,j) + u(i,j,k)
                       vav(i,j) = vav(i,j) + v(i,j,k)
                    endif
                 enddo
              enddo
           enddo
           
           do i = 1,nptsx,1
              do j = 1,nptsy,1
                 uav(i,j) = uav(i,j)/(nptsz-1.)
                 vav(i,j) = vav(i,j)/(nptsz-1.)
              enddo
           enddo
           
           maxx = 0.
           maxy = 0.
           do i = 1,nptsx,1
              do j = 1,nptsy,1
                 Difx(i,j) = abs(uav(i,j)*H(i,j)/ds_dx(i,j))
                 Dify(i,j) = abs(vav(i,j)*H(i,j)/ds_dy(i,j))
                 
                 if(Difx(i,j).ne.Difx(i,j)-1.)then
                    if(Difx(i,j).gt.maxx)then
                       maxx = Difx(i,j)
                    endif
                 endif
                 
                 if(Dify(i,j).ne.Dify(i,j)-1.)then
                    if(Dify(i,j).gt.maxy)then
                       maxy = Dify(i,j)
                    endif
                 endif
              enddo
           enddo
           do i = 1,nptsx,1
              do j = 1,nptsy,1
                 if(Difx(i,j).ne.Difx(i,j))then
                    Difx(i,j) = maxx/1.e10
                    write(6,*) "Difx Nan",i,j
                 elseif(Difx(i,j).eq.Difx(i,j)-1.)then
                    Difx(i,j) = 0.
c                    write(6,*) "Difx inf",i,j
                 endif
                 if(Dify(i,j).ne.Dify(i,j))then
                    Dify(i,j) = maxy/1.e10
                    write(6,*) "Dify Nan",i,j
                 elseif(Dify(i,j).eq.Dify(i,j)-1.)then
                    Dify(i,j) = 0.
c                    write(6,*) "Dify inf",i,j,dify(i,j)
                 endif
              enddo
           enddo
c     aa, ir, jc give sparse matrix in coordinate form
c  use diffusion at time n
           call topo_sparse(nptsx,nptsy,nptsz,dx,dy,dt,f,aa,ir,jc,H,Difx
     &          ,Dify,rr,length,ibase,uav,vav,w)
           write(6,*) "topo_sparse success"



c transform to CSR
           call acoocsr(nrow,nnz,aa,ir,jc,aao,jao,iao)
           write(6,*) "acoosr success"

        job = 1
c scales rows of A so that L2 norm is 1
        write(6,*) "begin aroscal"
        call aroscal(nrow,job,2,aao,jao,iao,scaletmp,aao,jao,iao,ierr)
        write(6,*) "aroscal end"
        if (ierr .ne. 0) then
          write (*,*) 'returned ierr .ne. 0 in roscal',ierr
        endif
c scale RHS and preconditioner by same factor
        do i=1,nrow,1         
           rr(i)=rr(i)*scaletmp(i)
           bb(i)=bb(i)*scaletmp(i)
        enddo
        write(6,*) "rhs scaled"
cc scales columns of A so that L2 norm is 1
        call acoscal(nrow,job,2,aao,jao,iao,scaletmp,aao,jao,iao,ierr)
        write(6,*) "acoscal end"
        if (ierr .ne. 0)then
           write (*,*) 'returned ierr .ne. 0 in coscal',ierr
        endif
        droptol=1.e-10
        lfil=20
cc LU decomposition
        write(*,*) "Start of ilut"
 
        call ilut(nrow,aao,jao,iao,lfil,droptol,
     &       alu,jlu,ju,(nrow*nrow),ww,jw,ierr)
        write(*,*) "end of ilut"
        write(6,*)"ilut ierr = ",ierr
c        goto 3
c solving        
c starting guess for topo at next step
       do i=1,nptsx,1
          do j=1,nptsy,1 
             if(((i-1)*nptsy +j).le.(nptsx*nptsy))then
                uu((i-1)*nptsy +j) = (H(i,j)+dH_dt(i,j)*dt)
     &               /scaletmp((i-1)*nptsy +j)
             else
                write(*,*) "uu index too high"
             endif
          enddo
       enddo
           

        itmax=5000
        eps=1.e-20
c        do i=1,nrow,1
c           uu(i)=0.
c        enddo
        write(*,*) "Start of pgmres"
        call pgmres(nrow,20,rr,uu,eps,itmax,0,
     &       aao,jao,iao,alu,jlu,ju,ierr)
        write(*,*) "end of pgmres"
        write(6,*)"pgmres ierr = ",ierr

c only need this if use second, column scaling
       do i = 1,nrow,1
          uu(i)=uu(i)*scaletmp(i)
        enddo
        write(6,*) "uu scale"


        do i = 1,nptsx,1
           do j = 1,nptsy,1
              dH_dt(i,j) = (uu((i-1)*nptsy +j) - H(i,j))/dt
              H_old(i,j) = H(i,j)
              
              H(i,j) = uu((i-1)*nptsy +j)
              s(i,j) = H(i,j)/(f+1.)
              if(H(i,j).le.0)then 
                 write(6,*) "error H 0",H(i,j),H_old(i,j),i,j
                 write(6,*) Difx(i,j),Dify(i,j),ds_dx(i,j),ds_dy(i,j)
                 ierr=1
                 goto 3
              endif
           enddo
        enddo
        if(any(H.le.0))then
           write(6,*) "error H 0"
           ierr = 1
        else
           ierr=0
        endif
        
        deallocate(aa,ir,jc,rr,aao,iao,jao,uu,scaletmp,a,bb,c,
     &       alu,jlu,ww,jw,ju)
    
 
 3    return
      end

      subroutine topo_vect_i_orig(nptsx,nptsy,dx,Difx,dt,H,aa,bb,
     &     cc,rr,f,j,hmin,uav,Dify,length)
      implicit none
      integer*4 nptsx,i,nptsy,j,length
      real*8 Difx(nptsx,nptsy),dx,dt,H(nptsx,nptsy),hmin
      real*8 aa(nptsx),bb(nptsx),cc(nptsx),rr(nptsx),f

      real*8 alpha,uav(nptsx,nptsy),Dify(nptsx,nptsy)

      alpha = (1. - (f/(f+1.)))*((dt/2.)/(dx**2.))
      do i = 1,nptsx,1
        aa(i) = -(alpha*0.5*(Difx(i,j)+Difx(i-1,j)))
        if(i.eq.nptsx) aa(i) = -2.*(alpha*0.5*(Difx(i,j)+Difx(i-1,j)))


        bb(i) = (1. + (alpha*0.5*(Difx(i+1,j)+Difx(i,j))) +
     &       (alpha*0.5*(Difx(i,j)+Difx(i-1,j))) )
        if(i.eq.1)bb(i) = (1. + (alpha*0.5*(Difx(i+1,j)+Difx(i,j))) +
     &       (alpha*0.5*(Difx(i,j)+Difx(i+1,j))) )
        if(i.eq.nptsx)bb(i) = (1. + (alpha*0.5*(Difx(i,j)+Difx(i-1,j)))
     $       +(alpha*0.5*(Difx(i-1,j)+Difx(i,j))) )

        cc(i) = -(alpha*0.5*(Difx(i+1,j)+Difx(i,j)))
        if(i.eq.1) cc(i) = -2.*(alpha*0.5*(Difx(i+1,j)+Difx(i,j)))


        rr(i) = H(i,j) +
     &       (alpha*((0.5*(Difx(i+1,j)+Difx(i,j))*(H(i+1,j) - H(i,j))) -
     &       (0.5*(Difx(i,j)+Difx(i-1,j))*(H(i,j) - H(i-1,j)))))
        if(i.eq.1) rr(i) = H(i,j) +
     &       (alpha*((0.5*(Difx(i+1,j)+Difx(i,j))*(H(i+1,j) - H(i,j))) -
     &       (0.5*(Difx(i,j)+Difx(i+1,j))*(H(i,j) - H(i+1,j)))))
        if(i.eq.nptsx)rr(i) = H(i,j) +
     &       (alpha*((0.5*(Difx(i,j)+Difx(i-1,j))*(H(i,j) - H(i-1,j))) -
     &       (0.5*(Difx(i-1,j)+Difx(i,j))*(H(i-1,j) - H(i,j)))))


        if(j.eq.1.and.i.le.length)then
           aa(i) = 0.
           bb(i) = 1.
           cc(i) = 0.
           rr(i) = H(i,j)
        endif
c        if(i.eq.1)then
c           aa(i) = 0.
c           bb(i) = 1.
c           cc(i) = 0.
c           rr(i) = H(i,j) - ((2.*uav(i+1,j)*dt*H(i+1,j))/dx)
c        endif



      enddo




      return
      end

      subroutine topo_vect_j_orig(nptsx,nptsy,dy,Dify,dt,H,aa,bb,cc,
     $     rr,f,i,hmin,hinit,vav,Difx,vedge,v,nptsz,s,w,length)
      implicit none
      integer*4 nptsx,i,nptsy,j,nptsz,length
      real*8 Dify(nptsx,nptsy),dy,dt,H(nptsx,nptsy),hmin,vedge(nptsx)
      real*8 aa(nptsy),bb(nptsy),cc(nptsy),rr(nptsy),f,vav(nptsx,nptsy)

      real*8 alpha,hinit,vmax,maxv,Difx(nptsx,nptsy),sinit(nptsx),
     &     v(nptsx,nptsy,nptsz),s(nptsx,nptsy),w(nptsx,nptsy,nptsz)

      maxv = 5.e-10
      vmax = maxv !- ((maxv)*(real(i)/real(nptsx)))

      alpha = (1. - (f/(f+1.)))*((dt/2.)/(dy**2.))
      do j = 1,nptsy,1
        aa(j) = -(alpha*0.5*(Dify(i,j)+Dify(i,j-1)))
        if(j.eq.nptsy) aa(j) = 0.
        if(j.eq.1)aa(j) = 0. !-2.*(alpha*0.5*(Dify(i,j+1)+Dify(i,j)))
 
        bb(j) = (1. + (alpha*0.5*(Dify(i,j+1)+Dify(i,j))) +
     &       (alpha*0.5*(Dify(i,j)+Dify(i,j-1))) )
        if(j.eq.nptsy)bb(j) = 1.
        if(j.eq.1)bb(j) = 1.!(1. + (alpha*0.5*(Dify(i,j+1)+Dify(i,j))) +
c     &       (alpha*0.5*(Dify(i,j+1)+Dify(i,j))) )


        cc(j) = -(alpha*0.5*(Dify(i,j+1)+Dify(i,j)))
        if(j.eq.1) cc(j) = 0.!-2.*(alpha*0.5*(Dify(i,j+1)+Dify(i,j)))
        if(j.eq.nptsy) cc(j) = 0.


        rr(j) = H(i,j) +
     &       (alpha*((0.5*(Dify(i,j+1)+Dify(i,j))*(H(i,j+1) - H(i,j))) -
     &       (0.5*(Dify(i,j)+Dify(i,j-1))*(H(i,j) - H(i,j-1)))))
        if(j.eq.1) rr(j) = H(i,j) !+ (alpha*((0.5*(Dify(i,j+1)+Dify(i,j))
c     $       *(H(i,j+1) - H(i,j))) -(0.5*(Dify(i,j+1)+Dify(i,j))*(H(i,j
c     $       +1) - H(i,j)))))
        if(j.eq.nptsy)rr(j) = H(i,j) !-
c     &       (((vav(i,j)*H(i,j)*dt) - (vav(i,j-1)*H(i,j-1)*dt))/dy)


        if(j.eq.1)then
           aa(j) = 0.
           bb(j) = 1.
           cc(j) = 0.
           rr(j) = H(i,j)!-(vav(i,j)*H(i,j)*dt/dy)
        endif


      enddo


      return
      end


      subroutine topo_vect_i(nptsx,nptsy,dx,Difx,dt,H,aa,bb,
     &     cc,rr,f,j,hmin,uav,Dify,length)
      implicit none
      integer*4 nptsx,i,nptsy,j,length
      real*8 Difx(nptsx,nptsy),dx,dt,H(nptsx,nptsy),hmin
      real*8 aa(nptsx),bb(nptsx),cc(nptsx),rr(nptsx),f

      real*8 alpha,uav(nptsx,nptsy),Dify(nptsx,nptsy)

      alpha = (1. - (f/(f+1.)))*((dt/2.)/(dx**2.))
      do i = 1,nptsx,1
        aa(i) = -(alpha*0.5*(Difx(i,j)+Difx(i-1,j)))
        if(i.eq.1) aa(i)=0.
        if(i.eq.nptsx) aa(i)=0.
c aa(i) = -2.*(alpha*0.5*(Difx(i,j)+Difx(i-1,j)))


        bb(i) = (1. + (alpha*0.5*(Difx(i+1,j)+Difx(i,j))) +
     &       (alpha*0.5*(Difx(i,j)+Difx(i-1,j))) )
        if(i.eq.1)bb(i) =1.+alpha*(Difx(i+1,j)+Difx(i,j))
c 1.+(alpha*(Difx(i+1,j)+Difx(i,j))
c     &       +alpha*(Difx(i+2,j)+Difx(i+1,j)-(Difx(i+1,j)+Difx(i,j))))
c                   !(1. + (alpha*0.5*(Difx(i+1,j)+Difx(i,j))) +
c     &       (alpha*0.5*(Difx(i,j)+Difx(i+1,j))) )
        if(i.eq.nptsx)bb(i)=1.
cbb(i) = (1. + (alpha*0.5*(Difx(i,j)+Difx(i-1,j)))
c     $       +(alpha*0.5*(Difx(i-1,j)+Difx(i,j))) )

        cc(i) = -(alpha*0.5*(Difx(i+1,j)+Difx(i,j)))
        if(i.eq.1) cc(i) = -(alpha*(Difx(i+1,j)+Difx(i,j)))
c     -2.*(alpha*0.5*(Difx(i+1,j)+Difx(i,j)))
c     $       -alpha*(Difx(i+2,j)+Difx(i+1,j)-(Difx(i+1,j)+Difx(i,j)))
        if(i.eq.nptsx) cc(i)=0.

        rr(i) = H(i,j) +
     &       (alpha*((0.5*(Difx(i+1,j)+Difx(i,j))*(H(i+1,j) - H(i,j))) -
     &       (0.5*(Difx(i,j)+Difx(i-1,j))*(H(i,j) - H(i-1,j)))))
        if(i.eq.1) rr(i) = H(i,j) +
     &       alpha*(Difx(i+1,j)+Difx(i,j))*(H(i+1,j)-H(i,j))

c     &       (alpha*((0.5*(Difx(i+1,j)+Difx(i,j))*(H(i+1,j) - H(i,j))) -
c     &       (0.5*(Difx(i,j)+Difx(i+1,j))*(H(i,j) - H(i+1,j)))))
        if(i.eq.nptsx)  rr(i)=H(i,j)!rr(i) =H(i,j) + 
c     &       (alpha*((0.5*(Difx(i,j)+Difx(i-1,j))*(H(i,j) - H(i-1,j))) -
c     &       (0.5*(Difx(i-1,j)+Difx(i,j))*(H(i-1,j) - H(i,j)))))

ccccc uncomment if want j=1 to stay at original height
c        if(j.eq.1.and.i.le.length)then
c           aa(i) = 0.
c           bb(i) = 1.
c           cc(i) = 0.
c           rr(i) = H(i,j)
c        endif
c        if(i.eq.1)then
c           aa(i) = 0.
c           bb(i) = 1.
c           cc(i) = 0.
c           rr(i) = H(i,j) - ((2.*uav(i+1,j)*dt*H(i+1,j))/dx)
c        endif



      enddo

      


      return
      end

      subroutine topo_vect_j(nptsx,nptsy,dy,Dify,dt,H,aa,bb, cc,rr,f,i
     $     ,hmin,hinit,vav,Difx,vedge,v,nptsz,s,w,length)
      implicit none
      integer*4 nptsx,i,nptsy,j,nptsz,length
      real*8 Dify(nptsx,nptsy),dy,dt,H(nptsx,nptsy),hmin,vedge(nptsx)
      real*8 aa(nptsy),bb(nptsy),cc(nptsy),rr(nptsy),f,vav(nptsx,nptsy)

      real*8 alpha,hinit,vmax,maxv,Difx(nptsx,nptsy),
     &     v(nptsx,nptsy,nptsz),s(nptsx,nptsy),w(nptsx,nptsy,nptsz)

c      maxv = 5.e-10
c      vmax = maxv !- ((maxv)*(real(i)/real(nptsx)))
cccccc this is set up to allow elevation to drop at j=1 over time
cccccc to keep elevation constant change r(i,j) at j.eq.1 to H(i,j)
      alpha = (1. - (f/(f+1.)))*((dt/2.)/(dy**2.))
      do j = 1,nptsy,1
         aa(j) = -(alpha*0.5*(Dify(i,j)+Dify(i,j-1)))
         if(j.eq.nptsy) aa(j) = 0.
         if(j.eq.1)aa(j) =0.! -2.*(alpha*0.5*(Dify(i,j+1)+Dify(i,j))) 
         
         bb(j) = (1. + (alpha*0.5*(Dify(i,j+1)+Dify(i,j))) +
     &        (alpha*0.5*(Dify(i,j)+Dify(i,j-1))) )
         if(j.eq.nptsy)bb(j) = 1.
         if(j.eq.1)bb(j) = 1.+alpha*(Dify(i,j+1)+Dify(i,j))
c         (1. + (alpha*(Dify(i,j+2)+
c     $        2*Dify(i,j+1)+Dify(i,j))))


         cc(j) = -(alpha*0.5*(Dify(i,j+1)+Dify(i,j)))
        if(j.eq.1) cc(j)=-(alpha*(Dify(i,j+1)+Dify(i,j))) 
c     !-2.*(alpha*0.5*(Dify(i,j+1)+Dify(i,j)))
         if(j.eq.nptsy) cc(j) = 0.


         rr(j) = H(i,j) +
     &        (alpha*((0.5*(Dify(i,j+1)+Dify(i,j))*(H(i,j+1) - H(i,j)))-
     &        (0.5*(Dify(i,j)+Dify(i,j-1))*(H(i,j) - H(i,j-1)))))
         if(j.eq.1) rr(j) = H(i,j) + alpha*(Dify(i,j+1)+Dify(i,j))
     &        *(H(i,j+1)-H(i,j)) 
         if(j.eq.nptsy)rr(j) = H(i,j) !-
c     &       (((vav(i,j)*H(i,j)*dt) - (vav(i,j-1)*H(i,j-1)*dt))/dy)
         

c         if(j.eq.1)then
c            aa(j) = 0.
c            bb(j) = 1.
c            cc(j) = 0.
c            rr(j) = -(vav(i,j)*H(i,j)*dt/dy) !H(i,j)
c        endif


      enddo


      return
      end


      subroutine topo_sparse(nptsx,nptsy,nptsz,dx,dy,dt,f,aa,ir,jc,H,
     &     Difx,Dify,rr,length,ibase,uav,vav,w)
      implicit none
      integer*4 nptsx,nptsy,nptsz,i,j,ir(*),jc(*),
     &     q,length,ibase(nptsx,nptsy)
      real*8 dx,dy,dt,f,aa(*),uav(nptsx,nptsy),vav(nptsx,nptsy)
      real*8 H(nptsx,nptsy),Difx(nptsx,nptsy),w(nptsx,nptsy,nptsz)
      real*8 Dify(nptsx,nptsy),rr(nptsx*nptsy),alpha_x,alpha_y
      
      alpha_x=(1.-(f/(f+1.)))*dt/(2.*(dx**2.))
      alpha_y=(1.-(f/(f+1.)))*dt/(2.*(dy**2.))
      
      if(alpha_x.ne.alpha_x)write(6,*) "alpha_x"
      if(alpha_y.ne.alpha_y)write(6,*) "alpha_y"
      
      q = 1
      
      do i=1,nptsx,1
         do j=1,nptsy,1
            
            if(j.eq.1!.and.i.ne.1.and.i.ne.nptsx
     &           )then
ccccc velocities
c
ccc     i-1,j
cc               aa(q) =-uav(i-1,j)*dt/(4.*dx)
cc               ir(q) = (i-1)*nptsy + j
cc               jc(q) = ((i-1)-1)*nptsy + j
cc               q = q+1
cc     i,j
c               aa(q)= 1. - (vav(i,j)*dt/(2.*dy))
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + j
c               q = q+1 
cc     i,j+1
c               aa(q) = vav(i,j+1)*dt/(2.*dy)
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + j+1
c               q = q+1
ccc     i+1,j
cc               aa(q) = uav(i+1,j)*dt/(4.*dx)
cc               ir(q) = (i-1)*nptsy + j
cc               jc(q) = ((i+1)-1)*nptsy + j
cc               q = q+1 
cc     rr
c               rr((((i-1)*nptsy) + j)) =
c
c     &              H(i,j+1)*(-vav(i,j+1)*dt/(2.*dy))+
c     &              H(i,j)*(1. + (vav(i,j)*dt/(2.*dy)))!+
cc     &              H(i+1,j)*(- uav(i+1,j)*dt/(4.*dx))
cc     &              H(i-1,j)*(uav(i-1,j)*dt/(4.*dx))
ccccc constant H
c     i,j
               aa(q) = 1.
               ir(q) = (i-1)*nptsy + j
               jc(q) = (i-1)*nptsy + j
               q = q+1 
c     rhs
               rr((((i-1)*nptsy) + j)) = H(i,j)
c            elseif(j.eq.1.and.i.eq.1)then
c
c
cc     i,j
c               aa(q) = 1.-!(uav(i,j)*dt/(2.*dx))-
c     &              (vav(i,j)*dt/(2.*dy))
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + j
c               q = q+1
ccc     i+1,j
cc               aa(q) = uav(i+1,j)*dt/(2.*dx)
cc               ir(q) = (i-1)*nptsy + j
cc               jc(q) = ((i-1)-1)*nptsy + j
cc               q = q+1
cc     i, j+1
c               aa(q) = vav(i,j+1)*dt/(2.*dy)
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + j+1
c               q = q+1
cc rr
c               rr((((i-1)*nptsy) + j)) = 
c     &              H(i,j)*(1.+!(uav(i,j)*dt/(2.*dx))+
c     &              (vav(i,j)*dt/(2.*dy)))-
c     &              H(i,j+1)*(vav(i,j+1)*dt/(2.*dy))
cc     &              H(i+1,j)*(uav(i+1,j)*dt/(2.*dx))-
c            elseif(j.eq.1.and.i.eq.nptsx)then
ccccccc constant H
ccc     i,j
cc               aa(q) = 1.
cc               ir(q) = (i-1)*nptsy + j
cc               jc(q) = (i-1)*nptsy + j
cc               q = q+1 
ccc     rhs
cc               rr((((i-1)*nptsy) + j)) = H(i,j)
ccc     i-1,j
cc               aa(q) = -uav(i-1,j)*dt/(2.*dx)
cc               ir(q) = (i-1)*nptsy + j
cc               jc(q) = ((i-1)-1)*nptsy + j
cc               q = q+1
c
cc     i,j
c               aa(q) = 1.-!+(uav(i,j)*dt/(2.*dx))-
c     &              (vav(i,j)*dt/(2.*dy))
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + j
c               q = q+1
cc     i, j+1
c               aa(q) = vav(i,j+1)*dt/(2.*dy)
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + j+1
c               q = q+1
cc rr
c               rr((((i-1)*nptsy) + j)) = 
c     &              H(i,j)*(1.+!-(uav(i,j)*dt/(2.*dx))+
c     &              (vav(i,j)*dt/(2.*dy)))-
c     &              H(i,j+1)*(vav(i,j+1)*dt/(2.*dy))
cc     &              H(i-1,j)*(uav(i-1,j)*dt/(2.*dx))+
c            elseif(i.eq.nptsx.and.j.eq.nptsy)then
cc diffusion
cc     i-1,j
cc              aa(q) = -2.*alpha_x*(Difx(i,j)+Difx(i-1,j))/2.
cc              ir(q) = (i-1)*nptsy + j
cc               jc(q) = ((i-1)-1)*nptsy + j
cc               q = q+1
ccc     i,j-1
cc               aa(q) = -2.*alpha_y*(Dify(i,j)+Dify(i,j-1))/2.
cc               ir(q) = (i-1)*nptsy + j
cc               jc(q) = (i-1)*nptsy + (j-1)
cc               q = q+1
ccc     i,j
cc               aa(q) = 1. + (alpha_x*((Difx(i,j)+Difx(i-1,j))/2.)*2.) +
cc     &              (alpha_y*((Dify(i,j)+Dify(i,j-1))/2.)*2.)
cc               ir(q) = (i-1)*nptsy + j
cc               jc(q) = (i-1)*nptsy + j
cc               q = q+1
ccc     rhs
cc               rr((((i-1)*nptsy) + j)) = 
cc     &              H(i-1,j)*(alpha_x*2.*(Difx(i,j)+Difx(i-1,j))/2.)+
cc     &              H(i,j-1)*(alpha_y*2.*(Dify(i,j)+Dify(i,j-1))/2.)+
cc     &              H(i,j)*( 1. + 
cc     &              (-2.*alpha_x*(Difx(i,j)+Difx(i-1,j))/2.)+ 
cc     &              (-2.*alpha_y*(Dify(i,j)+Dify(i,j-1))/2.)) 
cc     i-1,j
c               aa(q) = -uav(i-1,j)*dt/(2.*dx)
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = ((i-1)-1)*nptsy + j
c               q = q+1
cc     i, j-1
c               aa(q) = -vav(i,j-1)*dt/(2.*dy)
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + j-1
c               q = q+1
cc     i,j
c               aa(q) = 1.+(uav(i,j)*dt/(2.*dx))+
c     &              (vav(i,j)*dt/(2.*dy))
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + j
c               q = q+1
cc rr
c               rr((((i-1)*nptsy) + j)) = 
c     &              H(i-1,j)*(uav(i-1,j)*dt/(2.*dx))+
c     &              H(i,j-1)*(vav(i,j-1)*dt/(2.*dy))+
c     &              H(i,j)*(1.-(uav(i,j)*dt/(2.*dx))-
c     &              (vav(i,j)*dt/(2.*dy)))
            elseif(i.eq.1.and.j.le.length.and.j.ne.1 !.and.j.ne.nptsy.and.j.ne.1
     &              )then
ccc diffusion
c     i,j-1 
               aa(q) = -(alpha_y/2.)*(Dify(i,j)+Dify(i,j-1))
               ir(q) = (i-1)*nptsy + j
               jc(q) = (i-1)*nptsy + j-1
               q = q+1
c     i,j
               aa(q) = 1.+
     &              (alpha_x/2.)*(Difx(i,j)+Difx(i+1,j)+
     &              Difx(i,j)+Difx(i+1,j))+
     &          (alpha_y/2.)*(Dify(i,j)+Dify(i,j+1)+
     &              Dify(i,j)+Dify(i,j-1))
               ir(q) = (i-1)*nptsy + j
               jc(q) = (i-1)*nptsy + j
               q = q+1
c     i,j+1
               aa(q) = -(alpha_y/2.)*(Dify(i,j)+Dify(i,j+1))
               ir(q) = (i-1)*nptsy + j
               jc(q) = (i-1)*nptsy + j+1
               q = q+1
c     i+1,j
               aa(q) = -(alpha_x/2.)*(Difx(i,j)+Difx(i+1,j)+
     &              Difx(i,j)+Difx(i+1,j))
               ir(q) = (i-1)*nptsy + j
               jc(q) = (i+1-1)*nptsy + j
               q = q+1

          rr((((i-1)*nptsy) + j)) =
     &              H(i,j-1)*((alpha_y/2.)*(Dify(i,j)+Dify(i,j-1)))+
     &              H(i,j)*(1.-(alpha_x/2.)*(Difx(i,j)+Difx(i+1,j)+
     &              Difx(i,j)+Difx(i+1,j))-(alpha_y/2.)*(Dify(i,j)+
     &              Dify(i,j+1)+Dify(i,j)+Dify(i,j-1)))+
     &              H(i,j+1)*((alpha_y/2.)*(Dify(i,j)+Dify(i,j+1)))+
     &              H(i+1,j)*((alpha_x/2.)*(Difx(i,j)+Difx(i+1,j)+
     &              Difx(i,j)+Difx(i+1,j)))

cc   i,j-1
c               aa(q)=-vav(i,j-1)*dt/(4.*dy)
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + j-1
c               q = q+1  
cc     i,j
c               aa(q) = 1. - (uav(i,j)*dt/(2.*dx))
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + j
c               q = q+1  
cc i,j+1
c               aa(q) = vav(i,j+1)*dt/(4.*dy)
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + j+1
c               q = q+1  
cc i+1,j
c               aa(q) = uav(i+1,j)*dt/(2.*dx)
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i+1-1)*nptsy + j
c               q = q+1  
c
cc     rr
c               rr((((i-1)*nptsy) + j)) =
c     &              H(i,j-1)*(vav(i,j-1)*dt/(4.*dy))+
c     &              H(i,j)*(1. + (uav(i,j)*dt/(2.*dx)))+
c     &              H(i,j+1)*(-vav(i,j+1)*dt/(4.*dy))+
c     &              H(i+1,j)*(-uav(i+1,j)*dt/(2.*dx))
               elseif(i.eq.1.and.j.gt.length)then
ccccc constant H
c     i,j
               aa(q) = 1.
               ir(q) = (i-1)*nptsy + j
               jc(q) = (i-1)*nptsy + j
               q = q+1 
c     rhs
               rr((((i-1)*nptsy) + j)) = H(i,j)
            elseif(i.eq.nptsx.and.j.le.length
     &              .and.j.ne.1)then
ccc diffusion
c     i-1,j
               aa(q) = -(alpha_x/2.)*(Difx(i,j)+Difx(i-1,j)+
     &              Difx(i,j)+Difx(i-1,j))
               ir(q) = (i-1)*nptsy + j
               jc(q) = (i-1-1)*nptsy + j
               q = q+1
c     i,j-1 
               aa(q) = -(alpha_y/2.)*(Dify(i,j)+Dify(i,j-1))
               ir(q) = (i-1)*nptsy + j
               jc(q) = (i-1)*nptsy + j-1
               q = q+1
c     i,j
               aa(q) = 1.+
     &              (alpha_x/2.)*(Difx(i,j)+Difx(i-1,j)+
     &              Difx(i,j)+Difx(i-1,j))+
     &          (alpha_y/2.)*(Dify(i,j)+Dify(i,j+1)+
     &              Dify(i,j)+Dify(i,j-1))
               ir(q) = (i-1)*nptsy + j
               jc(q) = (i-1)*nptsy + j
               q = q+1
c     i,j+1
               aa(q) = -(alpha_y/2.)*(Dify(i,j)+Dify(i,j+1))
               ir(q) = (i-1)*nptsy + j
               jc(q) = (i-1)*nptsy + j+1
               q = q+1


          rr((((i-1)*nptsy) + j)) =
     &              H(i-1,j)*((alpha_x/2.)*(Difx(i,j)+Difx(i-1,j)+
     &              Difx(i,j)+Difx(i-1,j)))+
     &              H(i,j-1)*((alpha_y/2.)*(Dify(i,j)+Dify(i,j-1)))+
     &              H(i,j)*(1.-(alpha_x/2.)*(Difx(i,j)+Difx(i-1,j)+
     &              Difx(i,j)+Difx(i-1,j))-(alpha_y/2.)*(Dify(i,j)+
     &              Dify(i,j+1)+Dify(i,j)+Dify(i,j-1)))+
     &              H(i,j+1)*((alpha_y/2.)*(Dify(i,j)+Dify(i,j+1)))

cc     i-1,j
c               aa(q) = -uav(i-1,j)*dt/(2.*dx)
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1-1)*nptsy + j
c               q = q+1
cc     i,j-1
c               aa(q) = -vav(i,j-1)*dt/(4.*dy)
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + j-1
c               q = q+1
cc     i,j
c               aa(q) = 1. +(uav(i,j)*dt/(2.*dx))
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + j
c               q = q+1
c
cc     i,j+1
c               aa(q) = (vav(i,j+1))*dt/(4.*dy)
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + j+1
c               q = q+1
c               
cc     rr
c               rr((((i-1)*nptsy) + j)) =
c     &              H(i-1,j)*(uav(i-1,j)*dt/(2.*dx))+
c     &              H(i,j-1)*(vav(i,j-1)*dt/(4.*dy))+
c     &              H(i,j)*(1. -(uav(i,j)*dt/(2.*dx)))+
c     &              H(i,j+1)*(-(vav(i,j+1))*dt/(4.*dy))

       elseif(i.eq.nptsx.and.j.gt.length)then
ccccc constant H
c     i,j
               aa(q) = 1.
               ir(q) = (i-1)*nptsy + j
               jc(q) = (i-1)*nptsy + j
               q = q+1 
c     rhs
               rr((((i-1)*nptsy) + j)) = H(i,j)

            elseif(j.eq.nptsy)then!.and.i.ne.1.and.i.ne.nptsx)then!.and.
c     &          ibase(i,j).eq.1)then

ccccc constant H
c     i,j
               aa(q) = 1.
               ir(q) = (i-1)*nptsy + j
               jc(q) = (i-1)*nptsy + j
               q = q+1 
c     rhs
               rr((((i-1)*nptsy) + j)) = H(i,j)
c diffusion
c     i-1,j
c              aa(q) = -1.*alpha_x*(Difx(i,j)+Difx(i-1,j))/2.
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = ((i-1)-1)*nptsy + j
c               q = q+1
cc     i,j-1
c              aa(q) = -2.*alpha_y*(Dify(i,j)+Dify(i,j-1))/2.
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + (j-1)
c               q = q+1
cc     i,j
c               aa(q) = 1. + (alpha_x*(((Difx(i,j)+Difx(i+1,j))/2.)+
c     &              ((Difx(i,j)+Difx(i-1,j))/2.))) +      
c     &              (alpha_y*((Dify(i,j)+Dify(i,j-1))/2.)*2.)         
c              ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + j
c               q = q+1
cc     i+1,j
c               aa(q) = -1.*alpha_x*(Difx(i,j)+Difx(i+1,j))/2.
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = ((i+1)-1)*nptsy + j
c               q = q+1
ccc     rhs
c               rr((((i-1)*nptsy) + j)) = 
c     &              H(i-1,j)*(alpha_x*(Difx(i,j)+Difx(i-1,j))/2.) +
c     &              H(i,j-1)*(alpha_y*2.*(Dify(i,j)+Dify(i,j-1))/2.) +
c     &              H(i,j)*(1.-(alpha_x*(((Difx(i,j)+Difx(i+1,j))/2.) +
c     &              ((Difx(i,j)+Difx(i-1,j))/2.))) +
c     &              (-2.*alpha_y*(Dify(i,j)+Dify(i,j-1))/2.)) +
c     &              H(i+1,j)*(alpha_x*(Difx(i,j)+Difx(i+1,j))/2.)
ccccc velocities
c
cc     i-1,j
c               aa(q) =-uav(i-1,j)*dt/(4.*dx)
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = ((i-1)-1)*nptsy + j
c               q = q+1
cc     i,j-1
c               aa(q) = -vav(i,j-1)*dt/(2.*dy)
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + j-1
c               q = q+1
cc     i,j
c               aa(q)= 1. + (vav(i,j)*dt/(2.*dy))
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + j
c               q = q+1 
cc     i+1,j
c               aa(q) = uav(i+1,j)*dt/(4.*dx)
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = ((i+1)-1)*nptsy + j
c               q = q+1 
cc     rr
c               rr((((i-1)*nptsy) + j)) =
c     &              H(i-1,j)*(uav(i-1,j)*dt/(4.*dx))+
c     &              H(i,j-1)*(vav(i,j-1)*dt/(2.*dy))+
c     &              H(i,j)*(1. - (vav(i,j)*dt/(2.*dy)))+
c     &              H(i+1,j)*(- uav(i+1,j)*dt/(4.*dx))

c               elseif(i.eq.1.and.j.eq.nptsy)then
c
cc     i,j-1
c               aa(q) = -vav(i,j-1)*dt/(2.*dy)
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + (j-1)
c               q = q+1
cc     i,j
c               aa(q) = 1. - (uav(i,j)*dt/(2.*dx))+
c     &              (vav(i,j)*dt/(2.*dy))
c               ir(q) = (i-1)*nptsy + j
c               jc(q) = (i-1)*nptsy + j
c               q = q+1
cc     i+1,j
c               aa(q) = uav(i+1,j)*dt/(2.*dx)
c              ir(q) = (i-1)*nptsy + j
c               jc(q) = ((i+1)-1)*nptsy + j
c              q = q+1
cc     rhs
c               rr((((i-1)*nptsy) + j)) = 
c     &              H(i,j-1)*(vav(i,j-1)*dt/(2.*dy)) +
c     &          H(i,j)*( 1. + (uav(i,j)*dt/(2.*dx))-
c     &              (vav(i,j)*dt/(2.*dy)))+
c     &              H(i+1,j)*(-uav(i+1,j)*dt/(2.*dx))
c

            else
c     i-1,j
               aa(q) = -1.*alpha_x*(Difx(i,j)+Difx(i-1,j))/2.
               ir(q) = (i-1)*nptsy + j
               jc(q) = ((i-1)-1)*nptsy + j
               q = q+1
c     i,j-1
               aa(q) = -1.*alpha_y*(Dify(i,j)+Dify(i,j-1))/2.
               ir(q) = (i-1)*nptsy + j
               jc(q) = (i-1)*nptsy + (j-1)
               q = q+1
c     i,j
               aa(q) = 1. + (alpha_x*(((Difx(i,j)+Difx(i+1,j))/2.)+
     &              ((Difx(i,j)+Difx(i-1,j))/2.))) + (alpha_y*
     &              (((Dify(i,j)+Dify(i,j+1))/2.)+((Dify(i,j)+
     &              Dify(i,j-1))/2.)))
               ir(q) = (i-1)*nptsy + j
               jc(q) = (i-1)*nptsy + j
               q = q+1
c    i,j+1 
               aa(q) = -1.*alpha_y*(Dify(i,j)+Dify(i,j+1))/2.
               ir(q) = (i-1)*nptsy + j
               jc(q) = (i-1)*nptsy +(j+1)
               q = q+1
c     i+1,j
               aa(q) = -1.*alpha_x*(Difx(i,j)+Difx(i+1,j))/2.
               ir(q) = (i-1)*nptsy + j
               jc(q) = ((i+1)-1)*nptsy + j
               q = q+1
c     rhs
               rr((((i-1)*nptsy) + j)) =
     &              H(i-1,j)*(alpha_x*(Difx(i,j)+Difx(i-1,j))/2.) +
     &              H(i,j-1)*(alpha_y*(Dify(i,j)+Dify(i,j-1))/2.) +
     &              H(i,j)*(1.-(alpha_x*(((Difx(i,j)+Difx(i+1,j))/2.)+
     &              ((Difx(i,j)+Difx(i-1,j))/2.))) - (alpha_y*
     &              (((Dify(i,j)+Dify(i,j+1))/2.)+
     &              ((Dify(i,j)+Dify(i,j-1))/2.)))) +
     &              H(i,j+1)*(alpha_y*(Dify(i,j)+Dify(i,j+1))/2.) +
     &              H(i+1,j)*(alpha_x*(Difx(i,j)+Difx(i+1,j))/2.)
               if(rr((((i-1)*nptsy) + j)).ne.rr((((i-1)*nptsy) + j)))
     &          then
               write(6,*) "difx",i,j,Difx(i-1,j),Difx(i,j-1),Difx(i,j),
     &              Difx(i,j+1),Difx(i+1,j)
               write(6,*) "dify",i,j,Dify(i-1,j),Dify(i,j-1),Dify(i,j),
     &              Dify(i,j+1),Dify(i+1,j)
               write(6,*) "H",i,j,H(i-1,j),H(i,j-1),H(i,j),
     &              H(i,j+1),H(i+1,j)
               endif
            endif

         enddo
      enddo
      write(6,*) "qmax", q-1
      return
      end

CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
C                  SPARSKIT2 subroutines...                           C
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC


c-----------------------------------------------------------------------
      subroutine dnscsr(nrow,ncol,nzmax,dns,ndns,a,ja,ia,ierr)
      real*8 dns(ndns,*),a(*)
      integer*4 ia(*),ja(*)
      integer*4 nzmax
c-----------------------------------------------------------------------
c Dense          to    Compressed Row Sparse
c-----------------------------------------------------------------------
c
c converts a densely stored matrix into a row orientied
c compactly sparse matrix. ( reverse of csrdns )
c Note: this routine does not check whether an element
c is small. It considers that a(i,j) is zero if it is exactly
c equal to zero: see test below.
c-----------------------------------------------------------------------
c on entry:
c---------
c
c nrow   = row-dimension of a
c ncol   = column dimension of a
c nzmax = maximum number of nonzero elements allowed. This
c         should be set to be the lengths of the arrays a and ja.
c dns   = input nrow x ncol (dense) matrix.
c ndns   = first dimension of dns.
c
c on return:
c----------
c
c a, ja, ia = value, column, pointer  arrays for output matrix
c
c ierr   = integer error indicator:
c         ierr .eq. 0 means normal retur
c         ierr .eq. i means that the the code stopped while
c         processing row number i, because there was no space left in
c         a, and ja (as defined by parameter nzmax).
c-----------------------------------------------------------------------
      ierr = 0
      next = 1
      ia(1) = 1
      do 4 i=1,nrow
         do 3 j=1, ncol
            if (dns(i,j) .eq. 0.0d0) goto 3
            if (next .gt. nzmax) then
               ierr = i
               return
            endif
            ja(next) = j
            a(next) = dns(i,j)
            next = next+1
 3       continue
         ia(i+1) = next
 4    continue
      return
c---- end of dnscsr ----------------------------------------------------
c-----------------------------------------------------------------------
      end
      subroutine acoocsr(nrow,nnz,a,ir,jc,ao,jao,iao)
c-----------------------------------------------------------------------
      real*8 a(*),ao(*)
      real*8 x
      integer*4 ir(*),jc(*),jao(*),iao(*)
c-----------------------------------------------------------------------
c  Coordinate     to   Compressed Sparse Row
c-----------------------------------------------------------------------
c converts a matrix that is stored in coordinate format
c  a, ir, jc into a row general sparse ao, jao, iao format.
c
c on entry:
c---------
c nrow   = dimension of the matrix
c nnz    = number of nonzero elements in matrix
c a,
c ir,
c jc    = matrix in coordinate format. a(k), ir(k), jc(k) store the nnz
c         nonzero elements of the matrix with a(k) = actual real value of
c          the elements, ir(k) = its row number and jc(k) = its column
c          number. The order of the elements is arbitrary.
c
c on return:
c-----------
c ir     is destroyed
c
c ao, jao, iao = matrix in general sparse matrix format with ao
c        continung the real values, jao containing the column indices,
c        and iao being the pointer to the beginning of the row,
c        in arrays ao, jao.
c
c Notes:
c------ This routine is NOT in place.  See coicsr
c
c------------------------------------------------------------------------
      do 1 k=1,nrow+1
         iao(k) = 0
 1    continue
c determine row-lengths.
      do 2 k=1, nnz
         iao(ir(k)) = iao(ir(k))+1
 2    continue
c starting position of each row..
      k = 1
      do 3 j=1,nrow+1
         k0 = iao(j)
         iao(j) = k
         k = k+k0
 3    continue
c go through the structure  once more. Fill in output matrix.
      do 4 k=1, nnz
         i = ir(k)
         j = jc(k)
         x = a(k)
         iad = iao(i)
         ao(iad) =  x
         jao(iad) = j
         iao(i) = iad+1
 4    continue
c shift back iao
      do 5 j=nrow,1,-1
         iao(j+1) = iao(j)
 5    continue
      iao(1) = 1
      return
c------------- end of coocsr -------------------------------------------
c-----------------------------------------------------------------------
      end


   
      SUBROUTINE LINBCG(n,a,b,c,x,q,itol,tol,itmax,iter,er)
c     from Numerical Recipes Press et al. 1992 p.79
c     originally accessed matrix A in Ax=b as common statement in subroutine
c     now a,b,c are vectors of tridiagonal matrix
c     q is the RHS vector,x the LHS vector
      implicit none
      INTEGER iter,itmax,itol,n,NMAX
      REAL*8 er,tol,a(n),b(n),c(n),q(n),x(n),EPS,nrm
      PARAMETER (NMAX=50000,EPS=1.d-14)
c     USES atimes,asolve,nrm
      INTEGER l
      REAL*8 ak,akden,qk,qkden,qknum,qnrm,dxnrm
      REAL*8 xnrm,zm1nrm,znrm,p(NMAX),pp(NMAX),r(NMAX),rr(NMAX)
      REAL*8 z(NMAX),zz(NMAX)


      iter=0
      call atimes(n,a,b,c,x,r,0)
      do l=1,n
         r(l)=q(l)-r(l)
         rr(l)=r(l)
      enddo
c     call atimes(n,a,b,c,r,rr,0)
      if(itol.eq.1) then
         qnrm=nrm(n,q,itol)
         call asolve(n,b,r,z,0)
      else if(itol.eq.2) then
         call asolve(n,b,q,z,0)
         qnrm=nrm(n,z,itol)
         call asolve(n,b,r,z,0)
      else if(itol.eq.3.or.itol.eq.4) then
         call asolve(n,b,q,z,0)
         qnrm=nrm(n,z,itol)
         call asolve(n,b,r,z,0)
         znrm=nrm(n,z,itol)
      else
c         pause ' illegal itol in linbcg '
      endif
 100  if (iter.le.itmax) then
         iter=iter+1
         call asolve(n,b,rr,zz,1)
         qknum=0.d0
         do l=1,n
            qknum=qknum+z(l)*rr(l)
         enddo
         if (iter.eq.1) then
            do l=1,n
               p(l)=z(l)
               pp(l)=zz(l)
            enddo
         else
            qk=qknum/qkden
            do l=1,n
               p(l)=qk*p(l)+z(l)
               pp(l)=qk*pp(l)+zz(l)
            enddo
         endif
         qkden=qknum
         call atimes(n,a,b,c,p,z,0)
         akden=0.d0
         do l=1,n
            akden=akden+z(l)*pp(l)
         enddo
         ak=qknum/akden
         call atimes(n,a,b,c,pp,zz,1)
         do l=1,n
            x(l)=x(l)+ak*p(l)
            r(l)=r(l)-ak*z(l)
            rr(l)=rr(l)-ak*zz(l)
         enddo
         call asolve(n,b,r,z,0)
         if(itol.eq.1) then
            er=nrm(n,r,itol)/qnrm
         else if(itol.eq.2) then
            er=nrm(n,z,itol)/qnrm
         else if(itol.eq.3.or.itol.eq.4) then
            zm1nrm=znrm
            znrm=nrm(n,z,itol)
            if(abs(zm1nrm-znrm).gt.EPS*znrm) then
               dxnrm=abs(ak)*nrm(n,p,itol)
               er=znrm/abs(zm1nrm-znrm)*dxnrm
            else
               er=znrm/qnrm
               goto 100
            endif
            xnrm=nrm(n,x,itol)
            if(er.le.0.5d0*xnrm) then
               er=er/xnrm
            else
               er=znrm/qnrm
               goto 100
            endif
         endif
c         write (*,*) 'iter=', iter, 'err=', er
         if(er.gt.tol) goto 100
      endif
      return
      END

      subroutine LINBCG_SPARSE(n,nnz,aa,ja,ia,a,b,c,x,q,itol,tol
     &     ,itmax,iter,er,ierr)
c     from Numerical Recipes Press et al. 1992 p.79
c     originally accessed matrix A in Ax=b as common statement in subroutine
c     now aa,ja,ia are vectors representing sparse matrix in CSR format
c     q is the RHS vector,x the LHS vector
c     ierr is used to check whether linbcg converges in the allowed no its.
c itol 2 is one I have implemented so itol 3= itol2 from NR, 4 -> 3 etc.
c     a,b,c is tridiagonal representation of preconditioner matrix
      implicit none
      INTEGER iter,itmax,itol,n,NMAX,nnz,ierr
      INTEGER ja(*),ia(*)
      REAL*8 er,tol,aa(*),q(n),a(n),b(n),c(n),x(n),EPS,nrm
      PARAMETER (NMAX=50000,EPS=1.d-14)
c     USES satimes,asolve,nrm
      INTEGER l
      REAL*8 ak,akden,qk,qkden,qknum,qnrm,dxnrm
      REAL*8 xnrm,zm1nrm,znrm,p(NMAX),pp(NMAX),r(NMAX),rr(NMAX)
      REAL*8 z(NMAX),zz(NMAX),init_res(NMAX)
c     solving A~^-1.A.x=A~^-1.q  
c     b are diagonal elements of A~
c     r are residuals
c     A~.z=r A~T.zz=rr
      open(43,file='convergence.out')
      iter=0
      z=0.
      zz=0.
      init_res=0.

c     r = A.x
      call satimes(nnz,n,aa,ja,ia,x,r,0)
      
      do l=1,n
         if(aa(l).ne.aa(l))write(6,*) "aa(l)",l
         if(r(l).ne.r(l))write(6,*) "r",l
         if(x(l).ne.x(l))write(6,*) "x",l
         init_res(l)=r(l)
c     r=q-A.x i.e. residual
         r(l)=q(l)-r(l)
c     rr=q-A.x
         rr(l)=r(l)
      enddo
c     call satimes(n,aa,ja,ia,r,rr,0)
      if(itol.eq.1.or.itol.eq.2) then
c     qnrm=||q||
         qnrm=nrm(n,q,itol)
c     z=r/b i.e. solve A~.z=r (b are components fo A~ which is diagonal)
         call asolve(n,b,r,z,0)
c         call tridag(a,b,c,z,r,n)
         do l=1,n
         if(b(l).ne.b(l))write(6,*) "itol b(l)",l
         if(r(l).ne.r(l))write(6,*) "itol r",l
         if(x(l).ne.x(l))write(6,*) "itol x",l
         if(z(l).ne.z(l))write(6,*) "itol z",l
         enddo
      else if(itol.eq.3) then
c     solve A~.z=q z=q/b
         call asolve(n,b,q,z,0)
c         call tridag(a,b,c,z,q,n)
c     qnrm =||z||=||q/b||
         qnrm=nrm(n,z,itol)
c     solve A~.z=r z=r/b
         call asolve(n,b,r,z,0)
c         call tridag(a,b,c,z,r,n)
      else if(itol.eq.4.or.itol.eq.5) then
c     solve A~.z=q z=q/b
c         call asolve(n,b,q,z,0)
         call tridag(a,b,c,z,q,n)
c     qnrm=||z||=||q/b||
         qnrm=nrm(n,z,itol)
c     solve A~.z=r
         call asolve(n,b,r,z,0)
c         call tridag(a,b,c,z,r,n)
c     znrm=||z||=||r/b||
         znrm=nrm(n,z,itol)
      else
         write(6,*)' illegal itol in linbcg '
      endif
 100  if (iter.le.itmax) then
         iter=iter+1
c     solve A~T.zz=rr
         call asolve(n,b,rr,zz,1)
c         call tridagt(a,b,c,zz,rr,n)
         do l=1,n
         if(b(l).ne.b(l))write(6,*) "itol b(l)",l
         if(rr(l).ne.rr(l))write(6,*) "itol rr",l
         if(a(l).ne.a(l))write(6,*) "itol a",l
         if(c(l).ne.c(l))write(6,*) "itol c",l
         if(zz(l).ne.zz(l))write(6,*) "itol zz",l
         enddo
         qknum=0.d0
         do l=1,n
c     qknum= sum(z*rr) (z=r/b for all itol)
            qknum=qknum+z(l)*rr(l)
         enddo
         if (iter.eq.1) then
            do l=1,n
c     p=r/b
              p(l)=z(l)
c     pp=rr/b
               pp(l)=zz(l)
            enddo
         else
            qk=qknum/qkden
            do l=1,n
               p(l)=qk*p(l)+z(l)
               pp(l)=qk*pp(l)+zz(l)
            enddo
         endif
         qkden=qknum
         call satimes(nnz,n,aa,ja,ia,p,z,0)
         akden=0.d0
         do l=1,n
            akden=akden+z(l)*pp(l)
         enddo
         ak=qknum/akden
         call satimes(nnz,n,aa,ja,ia,pp,zz,1)
         do l=1,n
            x(l)=x(l)+ak*p(l)
            r(l)=r(l)-ak*z(l)
            rr(l)=rr(l)-ak*zz(l)
         enddo
         call asolve(n,b,r,z,0)
c         call tridag(a,b,c,z,r,n)
         do l=1,n
         if(b(l).ne.b(l))write(6,*) "itol 4771 b(l)",l
         if(r(l).ne.r(l))write(6,*) "itol 4771 r",l
         if(a(l).ne.a(l))write(6,*) "itol 4771 a",l
         if(c(l).ne.c(l))write(6,*) "itol 4771 c",l
         if(z(l).ne.z(l))write(6,*) "itol 4771 z",l
         enddo
         if(itol.eq.1) then
            er=nrm(n,r,itol)/qnrm
            write(43,*)iter,er
            flush(43)
         else if(itol.eq.2) then
            qnrm=nrm(n,init_res,itol)
            er=nrm(n,r,itol)/qnrm
         else if(itol.eq.3) then
            er=nrm(n,z,itol)/qnrm
         else if(itol.eq.4.or.itol.eq.5) then
c     zm1nrm=||q-A.x||old/||b|| znrm= same but for this iter??
           zm1nrm=znrm
            znrm=nrm(n,z,itol)
            if(abs(zm1nrm-znrm).gt.EPS*znrm) then
               dxnrm=abs(ak)*nrm(n,p,itol)
               er=znrm/abs(zm1nrm-znrm)*dxnrm
            else
               er=znrm/qnrm
               goto 100
            endif
            xnrm=nrm(n,x,itol)
            if(er.le.0.5d0*xnrm) then
               er=er/xnrm
            else
               er=znrm/qnrm
               goto 100
            endif
         endif
c         write (*,*) 'iter=', iter, 'err=', er
         if(er.gt.tol) goto 100
      else
         write (6,*) 'iter=', iter, 'err=', er
         ierr=1
      endif
      close(43)
      return
      END

      REAL*8 FUNCTION nrm(n,sx,itol)
      INTEGER n,itol,i,isamax
      REAL*8 sx(n),snrm
      if(itol.le.4) then
         snrm=0.
         do i=1,n,1
            snrm=snrm+sx(i)**2
         enddo
         nrm=sqrt(snrm)
      else
         write(*,*) "itol > 4"
         isamax=1
         do i=1,n
            if (abs(sx(i)).gt.abs(sx(isamax))) isamax=i
         enddo
         nrm=abs(sx(isamax))
      endif
      return
      END
      
      SUBROUTINE atimes(n,a,b,c,x,r,itrnsp) 
      implicit none
      INTEGER n,itrnsp,ija,NMAX
      REAL*8 a(n),b(n),c(n),x(n),r(n),sa
      PARAMETER (NMAX=50000)
c     multiply matrix by x if itrnsp=0, otherwise transpose of matrix
      if(itrnsp.eq.0) then
         call triax(a,b,c,x,r,n)
      else
         call triatx(a,b,c,x,r,n)
      endif
      return
      END

      SUBROUTINE satimes(nnz,n,aa,ja,ia,x,r,itrnsp)
      implicit none
      INTEGER nnz,itrnsp,ija,NMAX,n,ja(nnz),ia(n+1)
      REAL*8 aa(nnz),x(n),r(n),sa
      PARAMETER (NMAX=50000)
c     multiply matrix by x if itrnsp=0, otherwise transpose of matrix
      if(itrnsp.eq.0) then
         call amux(n,x,r,aa,ja,ia)
      else
         call aatmux(n,x,r,aa,ja,ia)
      endif
      return
      END 
     
      SUBROUTINE asolve(n,b,r,x,itrnsp)
      implicit none
      INTEGER n,itrnsp,NMAX,l
      REAL*8 r(n),x(n),b(n)
      PARAMETER (NMAX=50000)
c     preconditioned matrix (A~) set to diagonal elements of A
c     find A~^-1 * r
c     itrnsp not currently used since A=Atranspose when A is diagonal
      do l=1,n,1
         if( b(l).eq.0)then
            write(6,*) "Component of Atilda =0 ",l
            return
         else
            x(l)=r(l)/b(l)
         endif
      enddo
      return
      END
      
      SUBROUTINE triax(a,b,c,x,r,n)
      INTEGER n
      REAL*8 a(n),b(n),c(n),x(n),r(n)
      INTEGER l
      do l=1,n,1
         if(l.eq.1) then
            r(l)=(b(l)*x(l))+(c(l)*x(l+1))
         elseif(l.eq.n) then
            r(l)=(a(l)*x(l-1))+(b(l)*x(l))
         else
            r(l)=(a(l)*x(l-1))+(b(l)*x(l))+(c(l)*x(l+1))
         endif
      enddo
      return
      END
      
      SUBROUTINE triatx(a,b,c,x,r,n)
      INTEGER n
      REAL*8 a(n-1),b(n),c(n-1),x(n),r(n)
      INTEGER l
      do l=1,n,1
         if (l.eq.1) then
            r(l)=(b(l)*x(l))+(a(l+1)*x(l+1))
         elseif (l.eq.n) then
            r(l)=(c(l-1)*x(l-1))+(b(l)*x(l))
         else
            r(l)=(c(l-1)*x(l-1))+(b(l)*x(l))+(a(l+1)*x(l+1))
         endif
      enddo
      return
      END



c fortran not case sensitive so this is also called by tridag
c n.b. order of r and u is reversed from numerical recipies
      SUBROUTINE TRIDAG(A,B,C,U,R,N)
c     from numerical recipies (p.40). solves for vector U
      PARAMETER (NMAX=100000)
      REAL*8 GAM(NMAX),A(N),B(N),C(N),R(N),U(N)
      IF(B(1).EQ.0.)stop 'TRIDAG failed - rewrite matrices'
      BET=B(1)
      U(1)=R(1)/BET
      DO 11 J=2,N
        GAM(J)=C(J-1)/BET
        BET=B(J)-A(J)*GAM(J)
        IF(BET.EQ.0.)stop 'TRIDAG failed'
        U(J)=(R(J)-A(J)*U(J-1))/BET
 11   CONTINUE
      DO 12 J=N-1,1,-1
        U(J)=U(J)-GAM(J+1)*U(J+1)
 12   CONTINUE
      RETURN
      END

c n.b. order of r and u is reversed from numerical recipies
c first take transpose of tridiagonal matrix, then solve
      SUBROUTINE TRIDAGT(A,B,C,U,R,N)
c     from numerical recipies (p.40). solves for vector U
      PARAMETER (NMAX=100000)
      REAL*8 GAM(NMAX),A(N),B(N),C(N),R(N),U(N)
      REAL*8 AT(N),CT(N)
      
      AT=0
      CT=0

      DO J=1,N-1,1
         AT(J+1)=C(J)
         CT(J)=A(J+1)
      ENDDO
      
      IF(B(1).EQ.0.)stop 'TRIDAGT failed - rewrite matrices'
      BET=B(1)
      U(1)=R(1)/BET
      DO 11 J=2,N
        GAM(J)=CT(J-1)/BET
        BET=B(J)-AT(J)*GAM(J)
        IF(BET.EQ.0.)stop 'TRIDAGT failed'
        U(J)=(R(J)-AT(J)*U(J-1))/BET
 11   CONTINUE
      DO 12 J=N-1,1,-1
        U(J)=U(J)-GAM(J+1)*U(J+1)
 12   CONTINUE
      RETURN
      END

c----------------------------------------------------------------------- 
      subroutine aroscal(nrow,job,nrm,a,ja,ia,diag,b,jb,ib,ierr) 
      real*8 a(*), b(*), diag(nrow) 
      integer*4 nrow,job,nrm,ja(*),jb(*),ia(nrow+1),ib(nrow+1),ierr 
c-----------------------------------------------------------------------
c scales the rows of A such that their norms are one on return
c 3 choices of norms: 1-norm, 2-norm, max-norm.
c-----------------------------------------------------------------------
c on entry:
c ---------
c nrow	= integer. The row dimension of A
c
c job   = integer. job indicator. Job=0 means get array b only
c         job = 1 means get b, and the integer arrays ib, jb.
c
c nrm   = integer. norm indicator. nrm = 1, means 1-norm, nrm =2
c                  means the 2-nrm, nrm = 0 means max norm
c
c a,
c ja,
c ia   = Matrix A in compressed sparse row format.
c 
c on return:
c----------
c
c diag = diagonal matrix stored as a vector containing the matrix
c        by which the rows have been scaled, i.e., on return 
c        we have B = Diag*A.
c
c b, 
c jb, 
c ib	= resulting matrix B in compressed sparse row sparse format.
c	    
c ierr  = error message. ierr=0     : Normal return 
c                        ierr=i > 0 : Row number i is a zero row.
c Notes:
c-------
c 1)        The column dimension of A is not needed. 
c 2)        algorithm in place (B can take the place of A).
c-----------------------------------------------------------------
      call arnrms (nrow,nrm,a,ja,ia,diag)
      ierr = 0
      do 1 j=1, nrow
         if (diag(j) .eq. 0.0d0) then
            ierr = j 
            return
         else
            diag(j) = 1.0d0/diag(j)
         endif
 1    continue
      call adiamua(nrow,job,a,ja,ia,diag,b,jb,ib)
      return
c-------end-of-roscal---------------------------------------------------
c-----------------------------------------------------------------------
      end
c-----------------------------------------------------------------------
      subroutine acoscal(nrow,job,nrm,a,ja,ia,diag,b,jb,ib,ierr) 
c----------------------------------------------------------------------- 
      real*8 a(*),b(*),diag(nrow) 
      integer*4 nrow,job,ja(*),jb(*),ia(nrow+1),ib(nrow+1),ierr 
c-----------------------------------------------------------------------
c scales the columns of A such that their norms are one on return
c result matrix written on b, or overwritten on A.
c 3 choices of norms: 1-norm, 2-norm, max-norm. in place.
c-----------------------------------------------------------------------
c on entry:
c ---------
c nrow	= integer. The row dimension of A
c
c job   = integer. job indicator. Job=0 means get array b only
c         job = 1 means get b, and the integer arrays ib, jb.
c
c nrm   = integer. norm indicator. nrm = 1, means 1-norm, nrm =2
c                  means the 2-nrm, nrm = 0 means max norm
c
c a,
c ja,
c ia   = Matrix A in compressed sparse row format.
c 
c on return:
c----------
c
c diag = diagonal matrix stored as a vector containing the matrix
c        by which the columns have been scaled, i.e., on return 
c        we have B = A * Diag
c
c b, 
c jb, 
c ib	= resulting matrix B in compressed sparse row sparse format.
c
c ierr  = error message. ierr=0     : Normal return 
c                        ierr=i > 0 : Column number i is a zero row.
c Notes:
c-------
c 1)        The column dimension of A is not needed. 
c 2)       algorithm in place (B can take the place of A).
c-----------------------------------------------------------------
      call acnrms (nrow,nrm,a,ja,ia,diag)
      ierr = 0
      do 1 j=1, nrow
         if (diag(j) .eq. 0.0) then
            ierr = j 
            return
         else
            diag(j) = 1.0d0/diag(j)
         endif
 1    continue
      call aamudia (nrow,job,a,ja,ia,diag,b,jb,ib)
      return
c--------end-of-coscal-------------------------------------------------- 
c-----------------------------------------------------------------------
      end
      subroutine arnrms   (nrow, nrm, a, ja, ia, diag) 
      real*8 a(*), diag(nrow), scal 
      integer*4 ja(*), ia(nrow+1) 
c-----------------------------------------------------------------------
c gets the norms of each row of A. (choice of three norms)
c-----------------------------------------------------------------------
c on entry:
c ---------
c nrow	= integer. The row dimension of A
c
c nrm   = integer. norm indicator. nrm = 1, means 1-norm, nrm =2
c                  means the 2-nrm, nrm = 0 means max norm
c
c a,
c ja,
c ia   = Matrix A in compressed sparse row format.
c 
c on return:
c----------
c
c diag = real vector of length nrow containing the norms
c
c-----------------------------------------------------------------
      do 1 ii=1,nrow
c
c     compute the norm if each element.
c     
         scal = 0.0d0
         k1 = ia(ii)
         k2 = ia(ii+1)-1
         if (nrm .eq. 0) then
            do 2 k=k1, k2
               scal = max(scal,abs(a(k) ) ) 
 2          continue
         elseif (nrm .eq. 1) then
            do 3 k=k1, k2
               scal = scal + abs(a(k) ) 
 3          continue
         else
            do 4 k=k1, k2
               scal = scal+a(k)**2
 4          continue
         endif 
         if (nrm .eq. 2) scal = sqrt(scal) 
         diag(ii) = scal
 1    continue
      return
c-----------------------------------------------------------------------
c-------------end-of-rnrms----------------------------------------------
      end 
c-----------------------------------------------------------------------
      subroutine acnrms   (nrow, nrm, a, ja, ia, diag) 
      real*8 a(*), diag(nrow) 
      integer*4 ja(*), ia(nrow+1) 
c-----------------------------------------------------------------------
c gets the norms of each column of A. (choice of three norms)
c-----------------------------------------------------------------------
c on entry:
c ---------
c nrow	= integer. The row dimension of A
c
c nrm   = integer. norm indicator. nrm = 1, means 1-norm, nrm =2
c                  means the 2-nrm, nrm = 0 means max norm
c
c a,
c ja,
c ia   = Matrix A in compressed sparse row format.
c 
c on return:
c----------
c
c diag = real vector of length nrow containing the norms
c
c-----------------------------------------------------------------
      do 10 k=1, nrow 
         diag(k) = 0.0d0
 10   continue
      do 1 ii=1,nrow
         k1 = ia(ii)
         k2 = ia(ii+1)-1
         do 2 k=k1, k2
            j = ja(k) 
c     update the norm of each column
            if (nrm .eq. 0) then
               diag(j) = max(diag(j),abs(a(k) ) ) 
            elseif (nrm .eq. 1) then
               diag(j) = diag(j) + abs(a(k) ) 
            else
               diag(j) = diag(j)+a(k)**2
            endif 
 2       continue
 1    continue
      if (nrm .ne. 2) return
      do 3 k=1, nrow
         diag(k) = sqrt(diag(k))
 3    continue
      return
c-----------------------------------------------------------------------
c------------end-of-cnrms-----------------------------------------------
      end 
      subroutine adiamua (nrow,job, a, ja, ia, diag, b, jb, ib)
      real*8 a(*), b(*), diag(nrow), scal
      integer*4 ja(*),jb(*), ia(nrow+1),ib(nrow+1) 
c-----------------------------------------------------------------------
c performs the matrix by matrix product B = Diag * A  (in place) 
c-----------------------------------------------------------------------
c on entry:
c ---------
c nrow	= integer. The row dimension of A
c
c job   = integer. job indicator. Job=0 means get array b only
c         job = 1 means get b, and the integer arrays ib, jb.
c
c a,
c ja,
c ia   = Matrix A in compressed sparse row format.
c 
c diag = diagonal matrix stored as a vector dig(1:n)
c
c on return:
c----------
c
c b, 
c jb, 
c ib	= resulting matrix B in compressed sparse row sparse format.
c	    
c Notes:
c-------
c 1)        The column dimension of A is not needed. 
c 2)        algorithm in place (B can take the place of A).
c           in this case use job=0.
c-----------------------------------------------------------------
      do 1 ii=1,nrow
c     
c     normalize each row 
c     
         k1 = ia(ii)
         k2 = ia(ii+1)-1
         scal = diag(ii) 
         do 2 k=k1, k2
            b(k) = a(k)*scal
 2       continue
 1    continue
c     
      if (job .eq. 0) return
c     
      do 3 ii=1, nrow+1
         ib(ii) = ia(ii)
 3    continue
      do 31 k=ia(1), ia(nrow+1) -1 
         jb(k) = ja(k)
 31   continue
      return
c----------end-of-diamua------------------------------------------------
c-----------------------------------------------------------------------
      end 
c----------------------------------------------------------------------- 
      subroutine aamudia (nrow,job, a, ja, ia, diag, b, jb, ib)
      real*8 a(*), b(*), diag(nrow) 
      integer*4 ja(*),jb(*), ia(nrow+1),ib(nrow+1) 
c-----------------------------------------------------------------------
c performs the matrix by matrix product B = A * Diag  (in place) 
c-----------------------------------------------------------------------
c on entry:
c ---------
c nrow	= integer. The row dimension of A
c
c job   = integer. job indicator. Job=0 means get array b only
c         job = 1 means get b, and the integer arrays ib, jb.
c
c a,
c ja,
c ia   = Matrix A in compressed sparse row format.
c 
c diag = diagonal matrix stored as a vector dig(1:n)
c
c on return:
c----------
c
c b, 
c jb, 
c ib	= resulting matrix B in compressed sparse row sparse format.
c	    
c Notes:
c-------
c 1)        The column dimension of A is not needed. 
c 2)        algorithm in place (B can take the place of A).
c-----------------------------------------------------------------
      do 1 ii=1,nrow
c     
c     scale each element 
c     
         k1 = ia(ii)
         k2 = ia(ii+1)-1
         do 2 k=k1, k2
            b(k) = a(k)*diag(ja(k)) 
 2       continue
 1    continue
c     
      if (job .eq. 0) return
c     
      do 3 ii=1, nrow+1
         ib(ii) = ia(ii)
 3    continue
      do 31 k=ia(1), ia(nrow+1) -1 
         jb(k) = ja(k)
 31   continue
      return
c-----------------------------------------------------------------------
c-----------end-of-amudiag----------------------------------------------
      end 
c aplb   :   computes     C = A+B                                      c
      subroutine aaplb (nrow,ncol,job,a,ja,ia,b,jb,ib,
     *     c,jc,ic,nzmax,iw,ierr)
      real*8 a(*), b(*), c(*) 
      integer*4 ja(*),jb(*),jc(*),ia(nrow+1),ib(nrow+1),ic(nrow+1),
     *     iw(ncol)
c-----------------------------------------------------------------------
c performs the matrix sum  C = A+B. 
c-----------------------------------------------------------------------
c on entry:
c ---------
c nrow	= integer. The row dimension of A and B
c ncol  = integer. The column dimension of A and B.
c job   = integer. Job indicator. When job = 0, only the structure
c                  (i.e. the arrays jc, ic) is computed and the
c                  real values are ignored.
c
c a,
c ja,
c ia   = Matrix A in compressed sparse row format.
c 
c b, 
c jb, 
c ib	=  Matrix B in compressed sparse row format.
c
c nzmax	= integer. The  length of the arrays c and jc.
c         amub will stop if the result matrix C  has a number 
c         of elements that exceeds exceeds nzmax. See ierr.
c 
c on return:
c----------
c c, 
c jc, 
c ic	= resulting matrix C in compressed sparse row sparse format.
c	    
c ierr	= integer. serving as error message. 
c         ierr = 0 means normal return,
c         ierr .gt. 0 means that amub stopped while computing the
c         i-th row  of C with i=ierr, because the number 
c         of elements in C exceeds nzmax.
c
c work arrays:
c------------
c iw	= integer work array of length equal to the number of
c         columns in A.
c
c-----------------------------------------------------------------------
      logical values

      values = (job .ne. 0) 
      ierr = 0
      len = 0
      ic(1) = 1 
      do 1 j=1, ncol
         iw(j) = 0
 1    continue
c     
      do 500 ii=1, nrow
c     row i 
         do 200 ka=ia(ii), ia(ii+1)-1 
            len = len+1
            jcol    = ja(ka)
            if (len .gt. nzmax) goto 999
            jc(len) = jcol 
            if (values) c(len)  = a(ka) 
            iw(jcol)= len
 200     continue
c     
         do 300 kb=ib(ii),ib(ii+1)-1
            jcol = jb(kb)
            jpos = iw(jcol)
            if (jpos .eq. 0) then
               len = len+1
               if (len .gt. nzmax) goto 999
               jc(len) = jcol
               if (values) c(len)  = b(kb)
               iw(jcol)= len
            else
               if (values) c(jpos) = c(jpos) + b(kb)
            endif
 300     continue
         do 301 k=ic(ii), len
	    iw(jc(k)) = 0
 301     continue
         ic(ii+1) = len+1
 500  continue
      return
 999  ierr = ii
      return
c------------end of aplb ----------------------------------------------- 
      end
c csrcsc  : converts compressed sparse row format to compressed sparse c
      subroutine acsrcsc (n,job,ipos,a,ja,ia,ao,jao,iao)
      integer*4 ia(n+1),iao(n+1),ja(*),jao(*)
      real*8  a(*),ao(*)
c-----------------------------------------------------------------------
c Compressed Sparse Row     to      Compressed Sparse Column
c
c (transposition operation)   Not in place. 
c----------------------------------------------------------------------- 
c -- not in place --
c this subroutine transposes a matrix stored in a, ja, ia format.
c ---------------
c on entry:
c----------
c n	= dimension of A.
c job	= integer to indicate whether to fill the values (job.eq.1) of the
c         matrix ao or only the pattern., i.e.,ia, and ja (job .ne.1)
c
c ipos  = starting position in ao, jao of the transposed matrix.
c         the iao array takes this into account (thus iao(1) is set to ipos.)
c         Note: this may be useful if one needs to append the data structure
c         of the transpose to that of A. In this case use for example
c                call csrcsc (n,1,n+2,a,ja,ia,a,ja,ia(n+2)) 
c	  for any other normal usage, enter ipos=1.
c a	= real array of length nnz (nnz=number of nonzero elements in input 
c         matrix) containing the nonzero elements.
c ja	= integer array of length nnz containing the column positions
c 	  of the corresponding elements in a.
c ia	= integer of size n+1. ia(k) contains the position in a, ja of
c	  the beginning of the k-th row.
c
c on return:
c ---------- 
c output arguments:
c ao	= real array of size nzz containing the "a" part of the transpose
c jao	= integer array of size nnz containing the column indices.
c iao	= integer array of size n+1 containing the "ia" index array of
c	  the transpose. 
c
c----------------------------------------------------------------------- 
      call acsrcsc2 (n,n,job,ipos,a,ja,ia,ao,jao,iao)
      end
c-----------------------------------------------------------------------
      subroutine acsrcsc2 (n,n2,job,ipos,a,ja,ia,ao,jao,iao)
      integer*4 ia(n+1),iao(n2+1),ja(*),jao(*)
      real*8  a(*),ao(*)
c-----------------------------------------------------------------------
c Compressed Sparse Row     to      Compressed Sparse Column
c
c (transposition operation)   Not in place. 
c----------------------------------------------------------------------- 
c Rectangular version.  n is number of rows of CSR matrix,
c                       n2 (input) is number of columns of CSC matrix.
c----------------------------------------------------------------------- 
c -- not in place --
c this subroutine transposes a matrix stored in a, ja, ia format.
c ---------------
c on entry:
c----------
c n	= number of rows of CSR matrix.
c n2    = number of columns of CSC matrix.
c job	= integer to indicate whether to fill the values (job.eq.1) of the
c         matrix ao or only the pattern., i.e.,ia, and ja (job .ne.1)
c
c ipos  = starting position in ao, jao of the transposed matrix.
c         the iao array takes this into account (thus iao(1) is set to ipos.)
c         Note: this may be useful if one needs to append the data structure
c         of the transpose to that of A. In this case use for example
c                call csrcsc2 (n,n,1,n+2,a,ja,ia,a,ja,ia(n+2)) 
c	  for any other normal usage, enter ipos=1.
c a	= real array of length nnz (nnz=number of nonzero elements in input 
c         matrix) containing the nonzero elements.
c ja	= integer array of length nnz containing the column positions
c 	  of the corresponding elements in a.
c ia	= integer of size n+1. ia(k) contains the position in a, ja of
c	  the beginning of the k-th row.
c
c on return:
c ---------- 
c output arguments:
c ao	= real array of size nzz containing the "a" part of the transpose
c jao	= integer array of size nnz containing the column indices.
c iao	= integer array of size n+1 containing the "ia" index array of
c	  the transpose. 
c
c----------------------------------------------------------------------- 
c----------------- compute lengths of rows of transp(A) ----------------
      do 1 i=1,n2+1
         iao(i) = 0
 1    continue
      do 3 i=1, n
         do 2 k=ia(i), ia(i+1)-1 
            j = ja(k)+1
            iao(j) = iao(j)+1
 2       continue 
 3    continue
c---------- compute pointers from lengths ------------------------------
      iao(1) = ipos 
      do 4 i=1,n2
         iao(i+1) = iao(i) + iao(i+1)
 4    continue
c--------------- now do the actual copying ----------------------------- 
      do 6 i=1,n
         do 62 k=ia(i),ia(i+1)-1 
            j = ja(k) 
            next = iao(j)
            if (job .eq. 1)  ao(next) = a(k)
            jao(next) = i
            iao(j) = next+1
 62      continue
 6    continue
c-------------------------- reshift iao and leave ---------------------- 
      do 7 i=n2,1,-1
         iao(i+1) = iao(i)
 7    continue
      iao(1) = ipos
c--------------- end of csrcsc2 ---------------------------------------- 
c-----------------------------------------------------------------------
      end

c-----------------------------------------------------------------------
      subroutine aatmux (n, x, y, a, ja, ia)
      real*8 x(*), y(*), a(*) 
      integer*4 n, ia(*), ja(*)
c-----------------------------------------------------------------------
c         transp( A ) times a vector
c----------------------------------------------------------------------- 
c multiplies the transpose of a matrix by a vector when the original
c matrix is stored in compressed sparse row storage. Can also be
c viewed as the product of a matrix by a vector when the original
c matrix is stored in the compressed sparse column format.
c-----------------------------------------------------------------------
c
c on entry:
c----------
c n     = row dimension of A
c x     = real array of length equal to the column dimension of
c         the A matrix.
c a, ja,
c    ia = input matrix in compressed sparse row format.
c
c on return:
c-----------
c y     = real array of length n, containing the product y=transp(A)*x
c
c-----------------------------------------------------------------------
c     local variables 
c
      integer*4 i, k 
c-----------------------------------------------------------------------
c
c     zero out output vector
c 
      do 1 i=1,n
         y(i) = 0.0
 1    continue
c
c loop over the rows
c
      do 100 i = 1,n
         do 99 k=ia(i), ia(i+1)-1 
            y(ja(k)) = y(ja(k)) + x(i)*a(k)
 99      continue
 100  continue
c
      return
c-------------end-of-atmux---------------------------------------------- 
c-----------------------------------------------------------------------
      end
c----------------------------------------------------------------------- 
      subroutine aatmuxr (m, n, x, y, a, ja, ia)
      real*8 x(*), y(*), a(*) 
      integer*4 m, n, ia(*), ja(*)
c-----------------------------------------------------------------------
c         transp( A ) times a vector, A can be rectangular
c----------------------------------------------------------------------- 
c See also atmux.  The essential difference is how the solution vector
c is initially zeroed.  If using this to multiply rectangular CSC 
c matrices by a vector, m number of rows, n is number of columns.
c-----------------------------------------------------------------------
c
c on entry:
c----------
c m     = column dimension of A
c n     = row dimension of A
c x     = real array of length equal to the column dimension of
c         the A matrix.
c a, ja,
c    ia = input matrix in compressed sparse row format.
c
c on return:
c-----------
c y     = real array of length n, containing the product y=transp(A)*x
c
c-----------------------------------------------------------------------
c     local variables 
c
      integer*4 i, k 
c-----------------------------------------------------------------------
c
c     zero out output vector
c 
      do 1 i=1,m
         y(i) = 0.0
 1    continue
c
c loop over the rows
c
      do 100 i = 1,n
         do 99 k=ia(i), ia(i+1)-1 
            y(ja(k)) = y(ja(k)) + x(i)*a(k)
 99      continue
 100  continue
c
      return
c-------------end-of-atmuxr--------------------------------------------- 
c-----------------------------------------------------------------------
      end




      subroutine ilut(n,a,ja,ia,lfil,droptol,alu,jlu,ju,iwk,w,jw,ierr)
c-----------------------------------------------------------------------
      implicit none 
      integer n 
      real*8 a(*),alu(*),w(n+1),droptol
      integer ja(*),ia(n+1),jlu(*),ju(n),jw(2*n),lfil,iwk,ierr
c----------------------------------------------------------------------*
c                      *** ILUT preconditioner ***                     *
c      incomplete LU factorization with dual truncation mechanism      *
c----------------------------------------------------------------------*
c     Author: Yousef Saad *May, 5, 1990, Latest revision, August 1996  *
c----------------------------------------------------------------------*
c PARAMETERS                                                           
c-----------                                                           
c
c on entry:
c========== 
c n       = integer. The row dimension of the matrix A. The matrix 
c
c a,ja,ia = matrix stored in Compressed Sparse Row format.              
c
c lfil    = integer. The fill-in parameter. Each row of L and each row
c           of U will have a maximum of lfil elements (excluding the 
c           diagonal element). lfil must be .ge. 0.
c           ** WARNING: THE MEANING OF LFIL HAS CHANGED WITH RESPECT TO
c           EARLIER VERSIONS. 
c
c droptol = real*8. Sets the threshold for dropping small terms in the
c           factorization. See below for details on dropping strategy.
c
c  
c iwk     = integer. The lengths of arrays alu and jlu. If the arrays
c           are not big enough to store the ILU factorizations, ilut
c           will stop with an error message. 
c
c On return:
c===========
c
c alu,jlu = matrix stored in Modified Sparse Row (MSR) format containing
c           the L and U factors together. The diagonal (stored in
c           alu(1:n) ) is inverted. Each i-th row of the alu,jlu matrix
c           contains the i-th row of L (excluding the diagonal entry=1)
c           followed by the i-th row of U.
c
c ju      = integer array of length n containing the pointers to
c           the beginning of each row of U in the matrix alu,jlu.
c
c ierr    = integer. Error message with the following meaning.
c           ierr  = 0    --> successful return.
c           ierr .gt. 0  --> zero pivot encountered at step number ierr.
c           ierr  = -1   --> Error. input matrix may be wrong.
c                            (The elimination process has generated a
c                            row in L or U whose length is .gt.  n.)
c           ierr  = -2   --> The matrix L overflows the array al.
c           ierr  = -3   --> The matrix U overflows the array alu.
c           ierr  = -4   --> Illegal value for lfil.
c           ierr  = -5   --> zero row encountered.
c
c work arrays:
c=============
c jw      = integer work array of length 2*n.
c w       = real work array of length n+1.
c  
c----------------------------------------------------------------------
c w, ju (1:n) store the working array [1:ii-1 = L-part, ii:n = u] 
c jw(n+1:2n)  stores nonzero indicators
c 
c Notes:
c ------
c The diagonal elements of the input matrix must be  nonzero (at least
c 'structurally'). 
c
c----------------------------------------------------------------------* 
c---- Dual drop strategy works as follows.                             *
c                                                                      *
c     1) Theresholding in L and U as set by droptol. Any element whose *
c        magnitude is less than some tolerance (relative to the abs    *
c        value of diagonal element in u) is dropped.                   *
c                                                                      *
c     2) Keeping only the largest lfil elements in the i-th row of L   * 
c        and the largest lfil elements in the i-th row of U (excluding *
c        diagonal elements).                                           *
c                                                                      *
c Flexibility: one  can use  droptol=0  to get  a strategy  based on   *
c keeping  the largest  elements in  each row  of L  and U.   Taking   *
c droptol .ne.  0 but lfil=n will give  the usual threshold strategy   *
c (however, fill-in is then mpredictible).                             *
c----------------------------------------------------------------------*
c     locals
      integer ju0,k,j1,j2,j,ii,i,lenl,lenu,jj,jrow,jpos,len 
      real*8 tnorm, t, abs, s, fact 

      if (lfil .lt. 0) goto 998
c-----------------------------------------------------------------------
c     initialize ju0 (points to next element to be added to alu,jlu)
c     and pointer array.
c-----------------------------------------------------------------------
      ju0 = n+2
      jlu(1) = ju0
c
c     initialize nonzero indicator array. 
c

      do 1 j=1,n
         jw(n+j)  = 0
 1    continue
c-----------------------------------------------------------------------
c     beginning of main loop.
c-----------------------------------------------------------------------
      do 500 ii = 1, n
         j1 = ia(ii)
         j2 = ia(ii+1) - 1
         tnorm = 0.0d0
         do 501 k=j1,j2
            tnorm = tnorm+abs(a(k))
 501     continue
         if (tnorm .eq. 0.0) goto 999
         tnorm = tnorm/real(j2-j1+1)
c     
c     unpack L-part and U-part of row of A in arrays w 
c     
         lenu = 1
         lenl = 0
         jw(ii) = ii
         w(ii) = 0.0
         jw(n+ii) = ii
c
         do 170  j = j1, j2
            k = ja(j)
            t = a(j)
            if (k .lt. ii) then
               lenl = lenl+1
               jw(lenl) = k
               w(lenl) = t
               jw(n+k) = lenl
            else if (k .eq. ii) then
               w(ii) = t
            else
               lenu = lenu+1
               jpos = ii+lenu-1 
               jw(jpos) = k
               w(jpos) = t
               jw(n+k) = jpos
            endif
 170     continue
         jj = 0
         len = 0 

c     
c     eliminate previous rows
c     
 150     jj = jj+1
         if (jj .gt. lenl) goto 160
c-----------------------------------------------------------------------
c     in order to do the elimination in the correct order we must select
c     the smallest column index among jw(k), k=jj+1, ..., lenl.
c-----------------------------------------------------------------------
         jrow = jw(jj)
         k = jj
c     
c     determine smallest column index
c     
         do 151 j=jj+1,lenl
            if (jw(j) .lt. jrow) then
               jrow = jw(j)
               k = j
            endif
 151     continue
c
         if (k .ne. jj) then
c     exchange in jw
            j = jw(jj)
            jw(jj) = jw(k)
            jw(k) = j
c     exchange in jr
            jw(n+jrow) = jj
            jw(n+j) = k
c     exchange in w
            s = w(jj)
            w(jj) = w(k)
            w(k) = s
         endif
c
c     zero out element in row by setting jw(n+jrow) to zero.
c     
         jw(n+jrow) = 0
c
c     get the multiplier for row to be eliminated (jrow).
c     
         fact = w(jj)*alu(jrow)
         if (abs(fact) .le. droptol) goto 150
c     
c     combine current row and row jrow
c
         do 203 k = ju(jrow), jlu(jrow+1)-1
            s = fact*alu(k)
            j = jlu(k)
            jpos = jw(n+j)
            if (j .ge. ii) then
c     
c     dealing with upper part.
c     
               if (jpos .eq. 0) then
c
c     this is a fill-in element
c     
                  lenu = lenu+1
                  if (lenu .gt. n) goto 995
                  i = ii+lenu-1
                  jw(i) = j
                  jw(n+j) = i
                  w(i) = - s
               else
c
c     this is not a fill-in element 
c
                  w(jpos) = w(jpos) - s

               endif
            else
c     
c     dealing  with lower part.
c     
               if (jpos .eq. 0) then
c
c     this is a fill-in element
c     
                  lenl = lenl+1
                  if (lenl .gt. n) goto 995
                  jw(lenl) = j
                  jw(n+j) = lenl
                  w(lenl) = - s
               else
c     
c     this is not a fill-in element 
c     
                  w(jpos) = w(jpos) - s
               endif
            endif
 203     continue
c     
c     store this pivot element -- (from left to right -- no danger of
c     overlap with the working elements in L (pivots). 
c     
         len = len+1 
         w(len) = fact
         jw(len)  = jrow
         goto 150
 160     continue
c     
c     reset double-pointer to zero (U-part)
c     
         do 308 k=1, lenu
            jw(n+jw(ii+k-1)) = 0
 308     continue
c     
c     update L-matrix
c     

         lenl = len 
         len = min0(lenl,lfil)
c     
c     sort by quick-split
c
         call qsplit (w,jw,lenl,len)
c
c     store L-part
c 
         do 204 k=1, len 
            if (ju0 .gt. iwk) goto 996
            alu(ju0) =  w(k)
            jlu(ju0) =  jw(k)
            ju0 = ju0+1
 204     continue
c     
c     save pointer to beginning of row ii of U
c     
         ju(ii) = ju0
c
c     update U-matrix -- first apply dropping strategy 
c
         len = 0
         do k=1, lenu-1
            if (abs(w(ii+k)) .gt. droptol*tnorm) then 
               len = len+1
               w(ii+len) = w(ii+k) 
               jw(ii+len) = jw(ii+k) 
            endif
         enddo
         lenu = len+1
         len = min0(lenu,lfil)
c
         call qsplit (w(ii+1), jw(ii+1), lenu-1,len)
c
c     copy
c 
         t = abs(w(ii))
         if (len + ju0 .gt. iwk) goto 997
         do 302 k=ii+1,ii+len-1 
            jlu(ju0) = jw(k)
            alu(ju0) = w(k)
            t = t + abs(w(k) )
            ju0 = ju0+1
 302     continue
c     
c     store inverse of diagonal element of u
c     
         if (w(ii) .eq. 0.0) w(ii) = (0.0001 + droptol)*tnorm
c     
         alu(ii) = 1.0d0/ w(ii) 
c     
c     update pointer to beginning of next row of U.
c     
         jlu(ii+1) = ju0
c-----------------------------------------------------------------------
c     end main loop
c-----------------------------------------------------------------------

 500  continue
      ierr = 0

      return
c
c     incomprehensible error. Matrix must be wrong.
c     
 995  ierr = -1

      return
c     
c     insufficient storage in L.
c     
 996  ierr = -2

      return
c     
c     insufficient storage in U.
c     
 997  ierr = -3

      return
c     
c     illegal lfil entered.
c     
 998  ierr = -4

      return
c     
c     zero row encountered
c     
 999  ierr = -5

      return
c----------------end-of-ilut--------------------------------------------
c-----------------------------------------------------------------------
      end


        subroutine qsplit(a,ind,n,ncut)
        real*8 a(n)
        integer ind(n), n, ncut
c-----------------------------------------------------------------------
c     does a quick-sort split of a real array.
c     on input a(1:n). is a real array
c     on output a(1:n) is permuted such that its elements satisfy:
c
c     abs(a(i)) .ge. abs(a(ncut)) for i .lt. ncut and
c     abs(a(i)) .le. abs(a(ncut)) for i .gt. ncut
c
c     ind(1:n) is an integer array which permuted in the same way as a(*).
c-----------------------------------------------------------------------
        real*8 tmp, abskey
        integer itmp, first, last
c-----
        first = 1
        last = n
        if (ncut .lt. first .or. ncut .gt. last) return
c
c     outer loop -- while mid .ne. ncut do
c
 1      mid = first
        abskey = abs(a(mid))
        do 2 j=first+1, last
           if (abs(a(j)) .gt. abskey) then
              mid = mid+1
c     interchange
              tmp = a(mid)
              itmp = ind(mid)
              a(mid) = a(j)
              ind(mid) = ind(j)
              a(j)  = tmp
              ind(j) = itmp
           endif
 2      continue
c
c     interchange
c
        tmp = a(mid)
        a(mid) = a(first)
        a(first)  = tmp
c
        itmp = ind(mid)
        ind(mid) = ind(first)
        ind(first) = itmp
c
c     test for while loop
c
        if (mid .eq. ncut) return
        if (mid .gt. ncut) then
           last = mid-1
        else
           first = mid+1
        endif
        goto 1
c----------------end-of-qsplit------------------------------------------
c-----------------------------------------------------------------------
        end

      subroutine pgmres(n, im, rhs, sol,  eps, maxits, iout,
     *                    aa, ja, ia, alu, jlu, ju, ierr)
       implicit real*8 (a-h,o-z)
       integer n, im, maxits, iout, ierr, ja(*), ia(n+1), jlu(*), ju(n)
       real*8  rhs(n), sol(n), aa(*), alu(*), eps,vv(n,im+1)
       parameter (kmax=500)
       real*8 hh(kmax+1,kmax), c(kmax), s(kmax), rs(kmax+1),t
       data epsmac/1.d-16/

c      write(6,*)n
       n1 = n + 1
       its = 0
c parameters                                                           *
c-----------                                                           *
c on entry:                                                            *
c==========                                                            *
c                                                                      *
c n     == integer. The dimension of the matrix.                       *
c im    == size of krylov subspace:  should not exceed 50 in this      *
c          version (can be reset by changing parameter command for     *
c          kmax below)                                                 *
c rhs   == real vector of length n containing the right hand side.     *
c          Destroyed on return.                                        *
c sol   == real vector of length n containing an initial guess to the  *
c          solution on input. approximate solution on output           *
c eps   == tolerance for stopping criterion. process is stopped        *
c          as soon as ( ||.|| is the euclidean norm):                  *
c          || current residual||/||initial residual|| <= eps           *
c maxits== maximum number of iterations allowed                        *
c iout  == output unit number number for printing intermediate results *
c          if (iout .le. 0) nothing is printed out.                    *
c                                                                      *
c aa, ja,                                                              *
c ia    == the input matrix in compressed sparse row format:           *
c          aa(1:nnz)  = nonzero elements of A stored row-wise in order *
c          ja(1:nnz) = corresponding column indices.                   *
c          ia(1:n+1) = pointer to beginning of each row in aa and ja.  *
c          here nnz = number of nonzero elements in A = ia(n+1)-ia(1)  *
c                                                                      *
c alu,jlu== A matrix stored in Modified Sparse Row format containing   *
c           the L and U factors, as computed by subroutine ilut.       *
c                                                                      *
c ju     == integer array of length n containing the pointers to       *
c           the beginning of each row of U in alu, jlu as computed     *
c           by subroutine ILUT.                                        *
c                                                                      *
c on return:                          
c ierr  == integer. Error message with the following meaning.          *
c          ierr = 0 --> successful return.                             *
c          ierr = 1 --> convergence not achieved in itmax iterations.  *
c          ierr =-1 --> the initial guess seems to be the exact        *
c                       solution (initial residual computed was zero) 

c-------------------------------------------------------------
c outer loop starts here..
c-------------- compute initial residual vector --------------
       call amux (n, sol, vv, aa, ja, ia)
       do 21 j=1,n
          vv(j,1) = rhs(j) - vv(j,1)
 21    continue
c-------------------------------------------------------------
 20    ro = dnrm2(n, vv, 1)
c       if (iout .gt. 0 .and. its .eq. 0)
c     *      write(iout, 199) its, ro
       if (ro .eq. 0.0d0) goto 999
       t = 1.0d0/ ro
       do 210 j=1, n
          vv(j,1) = vv(j,1)*t
 210   continue
       if (its .eq. 0) eps1=eps
c     ** initialize 1-st term  of rhs of hessenberg system..
       rs(1) = ro
       i = 0
 4     i=i+1
       its = its + 1
       i1 = i + 1
       call lusol (n, vv(1,i), rhs, alu, jlu, ju)
       call amux (n, rhs, vv(1,i1), aa, ja, ia)
c-----------------------------------------
c     modified gram - schmidt...
c-----------------------------------------
       do 55 j=1, i
          t = ddot(n, vv(1,j),1,vv(1,i1),1)
          hh(j,i) = t
          call daxpy(n, -t, vv(1,j), 1, vv(1,i1), 1)
 55    continue
       t = dnrm2(n, vv(1,i1), 1)
       hh(i1,i) = t
       if ( t .eq. 0.0d0) goto 58
       t = 1.0d0/t
       do 57  k=1,n
          vv(k,i1) = vv(k,i1)*t
 57    continue
c
c     done with modified gram schimd and arnoldi step..
c     now  update factorization of hh
c
 58    if (i .eq. 1) goto 121
c--------perfrom previous transformations  on i-th column of h
       do 66 k=2,i
          k1 = k-1
          t = hh(k1,i)
          hh(k1,i) = c(k1)*t + s(k1)*hh(k,i)
          hh(k,i) = -s(k1)*t + c(k1)*hh(k,i)
 66    continue
 121   gam = sqrt(hh(i,i)**2 + hh(i1,i)**2)
c
c     if gamma is zero then any small value will do...
c     will affect only residual estimate
c
       if (gam .eq. 0.0d0) gam = epsmac
c
c     get  next plane rotation
c
       c(i) = hh(i,i)/gam
       s(i) = hh(i1,i)/gam
       rs(i1) = -s(i)*rs(i)
       rs(i) =  c(i)*rs(i)
c
c     detrermine residual norm and test for convergence-
c
       hh(i,i) = c(i)*hh(i,i) + s(i)*hh(i1,i)
       ro = abs(rs(i1))
 131   format(1h ,2e14.4)
c       if (iout .gt. 0 .and. mod(its,1) .eq. 0)
c     *      write(iout, 199) its, ro
       if (i .lt. im .and. (ro .gt. eps1))  goto 4
c
c     now compute solution. first solve upper triangular system.
c
       rs(i) = rs(i)/hh(i,i)
       do 30 ii=2,i
          k=i-ii+1
          k1 = k+1
          t=rs(k)
          do 40 j=k1,i
             t = t-hh(k,j)*rs(j)
 40       continue
          rs(k) = t/hh(k,k)
 30    continue
c
c     form linear combination of v(*,i)'s to get solution
c
       t = rs(1)
       do 15 k=1, n
          rhs(k) = vv(k,1)*t
 15    continue
       do 16 j=2, i
          t = rs(j)
          do 161 k=1, n
             rhs(k) = rhs(k)+t*vv(k,j)
 161      continue
 16    continue
c
c     call preconditioner.
c
       call lusol (n, rhs, rhs, alu, jlu, ju)
       do 17 k=1, n
          sol(k) = sol(k) + rhs(k)
 17    continue
c
c     restart outer loop  when necessary
c
       if (ro .le. eps1) goto 990
       if (its .ge. maxits) goto 991
c
c     else compute residual vector and continue..
c
       do 24 j=1,i
          jj = i1-j+1
          rs(jj-1) = -s(jj-1)*rs(jj)
          rs(jj) = c(jj-1)*rs(jj)
 24    continue
       do 25  j=1,i1
          t = rs(j)
          if (j .eq. 1)  t = t-1.0d0
          call daxpy (n, t, vv(1,j), 1,  vv, 1)
 25    continue
 199   format('   its =', i4, ' res. norm =', d20.6)
c     restart outer loop.
       goto 20
 990   ierr = 0
       return
 991   ierr = 1
       return
 999   continue
       ierr = -1
       return
c-----------------end of pgmres ---------------------------------------
c-----------------------------------------------------------------------
       end



      subroutine amux (n, x, y, a,ja,ia) 
      real*8  x(*), y(*), a(*) 
      integer n, ja(*), ia(*)
c-----------------------------------------------------------------------
c         A times a vector
c----------------------------------------------------------------------- 
c multiplies a matrix by a vector using the dot product form
c Matrix A is stored in compressed sparse row storage.
c
c on entry:
c----------
c n     = row dimension of A
c x     = real array of length equal to the column dimension of
c         the A matrix.
c a, ja,
c    ia = input matrix in compressed sparse row format.
c
c on return:
c-----------
c y     = real array of length n, containing the product y=Ax
c
c-----------------------------------------------------------------------
c local variables
c
      real*8 t
      integer i, k
c-----------------------------------------------------------------------
      do 100 i = 1,n
c
c     compute the inner product of row i with vector x
c 
         t = 0.0d0
         do 99 k=ia(i), ia(i+1)-1 
            t = t + a(k)*x(ja(k))
 99      continue
c
c     store result in y(i) 
c
         y(i) = t
 100  continue
c
      return
c---------end-of-amux---------------------------------------------------
c-----------------------------------------------------------------------
      end


	subroutine lusol(n, y, x, alu, jlu, ju)
        real*8 x(n), y(n), alu(*)
	integer n, jlu(*), ju(*)
c-----------------------------------------------------------------------
c
c This routine solves the system (LU) x = y, 
c given an LU decomposition of a matrix stored in (alu, jlu, ju) 
c modified sparse row format 
c
c-----------------------------------------------------------------------
c on entry:
c n   = dimension of system 
c y   = the right-hand-side vector
c alu, jlu, ju 
c     = the LU matrix as provided from the ILU routines. 
c
c on return
c x   = solution of LU x = y.     
c-----------------------------------------------------------------------
c 
c Note: routine is in place: call lusol (n, x, x, alu, jlu, ju) 
c       will solve the system with rhs x and overwrite the result on x . 
c
c-----------------------------------------------------------------------
c local variables
c
        integer i,k
c
c forward solve
c
        do 40 i = 1, n
           x(i) = y(i)
           do 41 k=jlu(i),ju(i)-1
              x(i) = x(i) - alu(k)* x(jlu(k))
 41        continue
 40     continue
c
c     backward solve.
c
	do 90 i = n, 1, -1
	   do 91 k=ju(i),jlu(i+1)-1
              x(i) = x(i) - alu(k)*x(jlu(k))
 91	   continue
           x(i) = alu(i)*x(i)
 90     continue
c
  	return
c----------------end of lusol ------------------------------------------
c-----------------------------------------------------------------------
	end



      subroutine daxpy(n,da,dx,incx,dy,incy)
c
c     constant times a vector plus a vector.
c     uses unrolled loops for increments equal to one.
c     jack dongarra, linpack, 3/11/78.
c     modified 12/3/93, array(1) declarations changed to array(*)
c
      double precision dx(*),dy(*),da
      integer i,incx,incy,ix,iy,m,mp1,n
c
      if(n.le.0)return
      if (da .eq. 0.0d0) return
      if(incx.eq.1.and.incy.eq.1)go to 20
c
c        code for unequal increments or equal increments
c          not equal to 1
c
      ix = 1
      iy = 1
      if(incx.lt.0)ix = (-n+1)*incx + 1
      if(incy.lt.0)iy = (-n+1)*incy + 1
      do 10 i = 1,n
        dy(iy) = dy(iy) + da*dx(ix)
        ix = ix + incx
        iy = iy + incy
   10 continue
      return
c
c        code for both increments equal to 1
c
c
c        clean-up loop
c
   20 m = mod(n,4)
      if( m .eq. 0 ) go to 40
      do 30 i = 1,m
        dy(i) = dy(i) + da*dx(i)
   30 continue
      if( n .lt. 4 ) return
   40 mp1 = m + 1
      do 50 i = mp1,n,4
        dy(i) = dy(i) + da*dx(i)
        dy(i + 1) = dy(i + 1) + da*dx(i + 1)
        dy(i + 2) = dy(i + 2) + da*dx(i + 2)
        dy(i + 3) = dy(i + 3) + da*dx(i + 3)
   50 continue
      return
      end

            DOUBLE PRECISION FUNCTION DNRM2 ( N, X, INCX )
*     .. Scalar Arguments ..
      INTEGER                           INCX, N
*     .. Array Arguments ..
      DOUBLE PRECISION                  X( * )
*     ..
*
*  DNRM2 returns the euclidean norm of a vector via the function
*  name, so that
*
*     DNRM2 := sqrt( x'*x )
*
*
*
*  -- This version written on 25-October-1982.
*     Modified on 14-October-1993 to inline the call to DLASSQ.
*     Sven Hammarling, Nag Ltd.
*
*
*     .. Parameters ..
      DOUBLE PRECISION      ONE         , ZERO
      PARAMETER           ( ONE = 1.0D+0, ZERO = 0.0D+0 )
*     .. Local Scalars ..
      INTEGER               IX
      DOUBLE PRECISION      ABSXI, NORM, SCALE, SSQ
*     .. Intrinsic Functions ..
      INTRINSIC             ABS, SQRT
*     ..
*     .. Executable Statements ..
      IF( N.LT.1 .OR. INCX.LT.1 )THEN
         NORM  = ZERO
      ELSE IF( N.EQ.1 )THEN
         NORM  = ABS( X( 1 ) )
      ELSE
         SCALE = ZERO
         SSQ   = ONE
*        The following loop is equivalent to this call to the LAPACK
*        auxiliary routine:
*        CALL DLASSQ( N, X, INCX, SCALE, SSQ )
*
         DO 10, IX = 1, 1 + ( N - 1 )*INCX, INCX
            IF( X( IX ).NE.ZERO )THEN
               ABSXI = ABS( X( IX ) )
               IF( SCALE.LT.ABSXI )THEN
                  SSQ   = ONE   + SSQ*( SCALE/ABSXI )**2
                  SCALE = ABSXI
               ELSE
                  SSQ   = SSQ   +     ( ABSXI/SCALE )**2
               END IF
            END IF
   10    CONTINUE
         NORM  = SCALE * SQRT( SSQ )
      END IF
*
      DNRM2 = NORM
      RETURN
*
*     End of DNRM2.
*
      END


      double precision function ddot(n,dx,incx,dy,incy)
c
c     forms the dot product of two vectors.
c     uses unrolled loops for increments equal to one.
c     jack dongarra, linpack, 3/11/78.
c     modified 12/3/93, array(1) declarations changed to array(*)
c
      double precision dx(*),dy(*),dtemp
      integer i,incx,incy,ix,iy,m,mp1,n
c
      ddot = 0.0d0
      dtemp = 0.0d0
      if(n.le.0)return
      if(incx.eq.1.and.incy.eq.1)go to 20
c
c        code for unequal increments or equal increments
c          not equal to 1
c
      ix = 1
      iy = 1
      if(incx.lt.0)ix = (-n+1)*incx + 1
      if(incy.lt.0)iy = (-n+1)*incy + 1
      do 10 i = 1,n
        dtemp = dtemp + dx(ix)*dy(iy)
        ix = ix + incx
        iy = iy + incy
   10 continue
      ddot = dtemp
      return
c
c        code for both increments equal to 1
c
c
c        clean-up loop
c
   20 m = mod(n,5)
      if( m .eq. 0 ) go to 40
      do 30 i = 1,m
        dtemp = dtemp + dx(i)*dy(i)
   30 continue
      if( n .lt. 5 ) go to 60
   40 mp1 = m + 1
      do 50 i = mp1,n,5
        dtemp = dtemp + dx(i)*dy(i) + dx(i + 1)*dy(i + 1) +
     *   dx(i + 2)*dy(i + 2) + dx(i + 3)*dy(i + 3) + dx(i + 4)*dy(i + 4)
   50 continue
   60 ddot = dtemp
      return
      end





