!=================================================================
      PROGRAM MAIN2D
!=================================================================
! GHOST code: Geophysical High Order Suite for Turbulence
!
! Numerically integrates the incompressible HD/MHD/Hall-MHD 
! equations in 2 dimensions using streamfunction or velocity 
! formulations with external forcing. A pseudo-spectral method 
! is used to compute spatial derivatives, while variable order 
! Runge-Kutta method is used to evolve the system in time 
! domain. To compile, you need the FFTW library installed on 
! your system. You should link with the FFTP subroutines 
! and use the FFTPLANS and MPIVARS modules (see the file 
! 'fftp_mod.f90').
!
! NOTATION: index 'i' is 'x' 
!           index 'j' is 'y'
!
! Conditional compilation options:
!           HD_SOL        builds the hydrodynamic (HD) solver
!           MHD_SOL       builds the MHD solver
!           MHDB_SOL      builds the MHD solver with uniform B_0
!           HMHD_SOL      builds the Hall-MHD solver (2.5D)
!
! 2004 Pablo D. Mininni.
!      Department of Physics, 
!      Facultad de Ciencias Exactas y Naturales.
!      Universidad de Buenos Aires.
!      e-mail: mininni@df.uba.ar 
!
! 1 Oct 2010: Main program for all solvers (HD/MHD/HMHD)
!=================================================================

!
! Definitions for conditional compilation

#ifdef HD_SOL
#define DNS_
#define STREAM_
#endif

#ifdef MHD_SOL
#define DNS_
#define STREAM_
#define VECPOT_
#endif

#ifdef MHDB_SOL
#define DNS_
#define STREAM_
#define VECPOT_
#define UNIFORMB_
#endif

#ifdef HMHD_SOL
#define DNS_
#define D25_
#define STREAM_
#define VECPOT_
#define HALLTERM_
#endif

!
! Modules

      USE fprecision
      USE commtypes
      USE mpivars
      USE filefmt
      USE iovar
      USE grid
      USE fft
      USE ali
      USE var
      USE kes
      USE order
      USE random
#ifdef DNS_
      USE dns
#endif
#ifdef HALLTERM_
      USE hall
#endif

      IMPLICIT NONE

!
! Arrays for the streamfunctions/fields and the external forcing

#ifdef STREAM_
      COMPLEX(KIND=GP), ALLOCATABLE, DIMENSION (:,:) :: ps,fk
#ifdef D25_
      COMPLEX(KIND=GP), ALLOCATABLE, DIMENSION (:,:) :: vz,fz
#endif
#endif
#ifdef VECPOT_
      COMPLEX(KIND=GP), ALLOCATABLE, DIMENSION (:,:) :: az,mk
#ifdef D25_
      COMPLEX(KIND=GP), ALLOCATABLE, DIMENSION (:,:) :: bz,mz
#endif
#endif

!
! Temporal data storage arrays

      COMPLEX(KIND=GP), ALLOCATABLE, DIMENSION (:,:) :: C1,C2
#ifdef VECPOT_
      COMPLEX(KIND=GP), ALLOCATABLE, DIMENSION (:,:) :: C3,C4,C5
#endif
#ifdef HALLTERM_
      COMPLEX(KIND=GP), ALLOCATABLE, DIMENSION (:,:) :: C6,C7
      COMPLEX(KIND=GP), ALLOCATABLE, DIMENSION (:,:) :: C8,C9
      COMPLEX(KIND=GP), ALLOCATABLE, DIMENSION (:,:) :: C10,C11
#endif
      REAL(KIND=GP), ALLOCATABLE, DIMENSION (:,:)    :: R1
#ifdef VECPOT_
      REAL(KIND=GP), ALLOCATABLE, DIMENSION (:,:)    :: R2
#endif

!
! Auxiliary variables

      COMPLEX(KIND=GP) :: cdump,jdump
      COMPLEX(KIND=GP) :: cdumq,jdumq
      DOUBLE PRECISION :: tmp,tmq
      DOUBLE PRECISION :: cputime1,cputime2
      DOUBLE PRECISION :: cputime3,cputime4

      REAL(KIND=GP) :: dt,nu,mu
      REAL(KIND=GP) :: kup,kdn
      REAL(KIND=GP) :: rmp,rmq
      REAL(KIND=GP) :: dump
      REAL(KIND=GP) :: stat
      REAL(KIND=GP) :: f0,u0
      REAL(KIND=GP) :: phase,ampl,cort
      REAL(KIND=GP) :: fparam0,fparam1,fparam2,fparam3,fparam4
      REAL(KIND=GP) :: fparam5,fparam6,fparam7,fparam8,fparam9
      REAL(KIND=GP) :: vparam0,vparam1,vparam2,vparam3,vparam4
      REAL(KIND=GP) :: vparam5,vparam6,vparam7,vparam8,vparam9
#ifdef VECPOT_
      REAL(KIND=GP) :: mkup,mkdn
      REAL(KIND=GP) :: m0,a0
      REAL(KIND=GP) :: mparam0,mparam1,mparam2,mparam3,mparam4
      REAL(KIND=GP) :: mparam5,mparam6,mparam7,mparam8,mparam9
      REAL(KIND=GP) :: aparam0,aparam1,aparam2,aparam3,aparam4
      REAL(KIND=GP) :: aparam5,aparam6,aparam7,aparam8,aparam9
#endif
#ifdef UNIFORMB_
      REAL(KIND=GP) :: by0
#endif

      INTEGER :: ini,step
      INTEGER :: tstep,cstep
      INTEGER :: sstep,fstep
      INTEGER :: bench,trans
      INTEGER :: seed,rand
      INTEGER :: outs,mult
      INTEGER :: t,o
      INTEGER :: i,j
      INTEGER :: ki,kj
      INTEGER :: tind,sind
      INTEGER :: timet,timec
      INTEGER :: times,timef

      TYPE(IOPLAN) :: planio
      CHARACTER(len=100) :: odir,idir

!
! Namelists for the input files

      NAMELIST / status / idir,odir,stat,mult,bench,outs,trans
      NAMELIST / parameter / dt,step,tstep,sstep,cstep,rand,cort,seed
      NAMELIST / velocity / f0,u0,kdn,kup,nu,fparam0,fparam1,fparam2
      NAMELIST / velocity / fparam3,fparam4,fparam5,fparam6,fparam7
      NAMELIST / velocity / fparam8,fparam9,vparam0,vparam1,vparam2
      NAMELIST / velocity / vparam3,vparam4,vparam5,vparam6,vparam7
      NAMELIST / velocity / vparam8,vparam9
#ifdef MAGFIELD_
      NAMELIST / magfield / m0,a0,mkdn,mkup,mu,corr,mparam0,mparam1
      NAMELIST / magfield / mparam2,mparam3,mparam4,mparam5,mparam6
      NAMELIST / magfield / mparam7,mparam8,mparam9,aparam0,aparam1
      NAMELIST / magfield / aparam2,aparam3,aparam4,aparam5,aparam6
      NAMELIST / magfield / aparam7,aparam8,aparam9
#endif
#ifdef UNIFORMB_
      NAMELIST / uniformb / by0
#endif
#ifdef HALLTERM_
      NAMELIST / hallparam / ep
#endif

!
! Initializes the MPI and I/O library

      CALL MPI_INIT(ierr)
      CALL MPI_COMM_SIZE(MPI_COMM_WORLD,nprocs,ierr)
      CALL MPI_COMM_RANK(MPI_COMM_WORLD,myrank,ierr)
      CALL range(1,n/2+1,nprocs,myrank,ista,iend)
      CALL range(1,n,nprocs,myrank,jsta,jend)
      CALL io_init(myrank,n,jsta,jend,planio)

!
! Initializes the FFT library
! Use FFTW_ESTIMATE or FFTW_MEASURE in short runs
! Use FFTW_PATIENT or FFTW_EXHAUSTIVE in long runs
! FFTW 2.x only supports FFTW_ESTIMATE or FFTW_MEASURE

      CALL fftp2d_create_plan(planrc,n,FFTW_REAL_TO_COMPLEX, &
                             FFTW_MEASURE)
      CALL fftp2d_create_plan(plancr,n,FFTW_COMPLEX_TO_REAL, &
                             FFTW_MEASURE)

!
! Allocates memory for distributed blocks

      ALLOCATE( C1(n,ista:iend), C2(n,ista:iend) )
#ifdef STREAM_
      ALLOCATE( ps(n,ista:iend), fk(n,ista:iend) )
#endif
#ifdef VECPOT_
      ALLOCATE( C3(n,ista:iend), C4(n,ista:iend) )
      ALLOCATE( C5(n,ista:iend) )
#endif
#ifdef HALLTERM_
      ALLOCATE( C6(n,ista:iend),  C7(n,ista:iend)  )
      ALLOCATE( C8(n,ista:iend),  C9(n,ista:iend)  )
      ALLOCATE( C10(n,ista:iend), C11(n,ista:iend) )
#endif
      ALLOCATE( ka(n), ka2(n,ista:iend) )
      ALLOCATE( R1(n,jsta:jend) )
#ifdef VECPOT_
      ALLOCATE( R2(n,jsta:jend) )
#endif

!
! Some constants for the FFT
!     kmax: maximum truncation for dealiasing
!     tiny: minimum truncation for dealiasing

      kmax = (real(n,kind=GP)/3.0_GP)**2
      tiny  = 1e-5_GP

!
! Builds the wave number and the square wave 
! number matrixes

      DO i = 1,n/2
         ka(i) = real(i-1,kind=GP)
         ka(i+n/2) = real(i-n/2-1,kind=GP)
      END DO
      DO i = ista,iend
         DO j = 1,n
            ka2(j,i) = ka(i)**2+ka(j)**2
         END DO
      END DO

! The following lines read the file 'parameter.txt'

!
! Reads general configuration flags from the namelist 
! 'status' on the external file 'parameter.txt'
!     idir : directory for unformatted input
!     odir : directory for unformatted output
!     stat : = 0 starts a new run
!            OR  gives the number of the file used to continue a run
!     mult : time step multiplier
!     bench: = 0 production run
!            = 1 benchmark run (no I/O)
!     outs : = 0 writes streamfunction [and vector potential (VECPOT_)]
!            = 1 writes vorticity [and current (MAGFIELD_)]
!     trans: = 0 skips energy transfer computation
!            = 1 performs energy transfer computation

      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=status)
         CLOSE(1)
      ENDIF
      CALL MPI_BCAST(idir,100,MPI_CHARACTER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(odir,100,MPI_CHARACTER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(stat,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mult,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(bench,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(outs,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(trans,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)

!
! Reads parameters that will be used to control the 
! time integration from the namelist 'parameter' on 
! the external file 'parameter.txt'
!     dt   : time step size
!     step : total number of time steps to compute
!     tstep: number of steps between binary output
!     sstep: number of steps between power spectrum output
!     cstep: number of steps between output of global quantities
!     rand : = 0 constant force
!            = 1 random phases
!     cort : time correlation of the external forcing
!     seed : seed for the random number generator

      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=parameter)
         CLOSE(1)
         dt = dt/real(mult,kind=GP)
         step = step*mult
         tstep = tstep*mult
         sstep = sstep*mult
         cstep = cstep*mult
         fstep = int(cort/dt)
      ENDIF
      CALL MPI_BCAST(dt,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(step,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(tstep,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(sstep,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(cstep,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fstep,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(rand,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(seed,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)

!
! Reads parameters for the velocity field from the 
! namelist 'velocity' on the external file 'parameter.txt' 
!     f0   : amplitude of the mechanical forcing
!     u0   : amplitude of the initial velocity field
!     kdn  : minimum wave number in v/mechanical forcing
!     kup  : maximum wave number in v/mechanical forcing
!     nu   : kinematic viscosity
!     fparam0-9 : ten real numbers to control properties of 
!            the mechanical forcing
!     vparam0-9 : ten real numbers to control properties of
!            the initial conditions for the velocity field

      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=velocity)
         CLOSE(1)
      ENDIF
      CALL MPI_BCAST(f0,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(u0,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(kdn,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(kup,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(nu,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam0,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam1,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam2,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam3,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam4,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam5,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam6,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam7,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam8,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(fparam9,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam0,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam1,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam2,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam3,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam4,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam5,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam6,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam7,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam8,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(vparam9,1,GC_REAL,0,MPI_COMM_WORLD,ierr)

#ifdef MAGFIELD_
!
! Reads parameters for the magnetic field from the 
! namelist 'magfield' on the external file 'parameter.txt' 
!     m0   : amplitude of the electromotive forcing
!     a0   : amplitude of the initial vector potential
!     mkdn : minimum wave number in B/electromotive forcing
!     mkup : maximum wave number in B/electromotive forcing
!     mu   : magnetic diffusivity
!     corr : correlation between the fields (0 to 1)
!     mparam0-9 : ten real numbers to control properties of 
!            the electromotive forcing
!     aparam0-9 : ten real numbers to control properties of
!            the initial conditions for the magnetic field

      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=magfield)
         CLOSE(1)
      ENDIF
      CALL MPI_BCAST(m0,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(a0,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mkdn,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mkup,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mu,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(corr,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam0,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam1,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam2,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam3,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam4,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam5,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam6,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam7,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam8,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(mparam9,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam0,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam1,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam2,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam3,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam4,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam5,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam6,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam7,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam8,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(aparam9,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
#endif

#ifdef UNIFORMB_
!
! Reads parameters for runs with a uniform magnetic 
! field from the namelist 'uniformb' on the external 
! file 'parameter.txt' 
!     by0: uniform magnetic field in y

      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=uniformb)
         CLOSE(1)
      ENDIF
      CALL MPI_BCAST(by0,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
#endif

#ifdef HALLTERM_
!
! Reads parameters for runs with the Hall effect 
! from the namelist 'hallparam' on the external 
! file 'parameter.txt' 
!     ep  : amplitude of the Hall effect
!     gspe: = 0 skips generalized helicity spectrum computation
!           = 1 computes the spectrum of generalized helicity

      IF (myrank.eq.0) THEN
         OPEN(1,file='parameter.txt',status='unknown',form="formatted")
         READ(1,NML=hallparam)
         CLOSE(1)
      ENDIF
      CALL MPI_BCAST(ep,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
#endif

!
! Sets the external forcing

      INCLUDE 'initialfv.f90'           ! mechanical forcing
#ifdef MAGFIELD_
      INCLUDE 'initialfb.f90'           ! electromotive forcing
#endif

! If stat=0 we start a new run.
! Generates initial conditions for the fields.

      timef = fstep
 IC : IF (stat.eq.0) THEN

      ini = 1
      sind = 0                          ! index for the spectrum
      tind = 0                          ! index for the binaries
      timet = tstep
      timec = cstep
      times = sstep
      INCLUDE 'initialv.f90'            ! initial velocity
#ifdef MAGFIELD_
      INCLUDE 'initialb.f90'            ! initial vector potential
#endif

      ELSE

! If stat.ne.0 a previous run is continued

      ini = int((stat-1)*tstep)
      tind = int(stat)
      sind = int(real(ini,kind=GP)/real(sstep,kind=GP)+1)
      WRITE(ext, fmtext) tind
      times = 0
      timet = 0
      timec = 0

#ifdef STREAM_
      CALL io_read(1,idir,'ps',ext,planio,R1)
      CALL fftp2d_real_to_complex(planrc,R1,ps,MPI_COMM_WORLD)
#ifdef D25_
      CALL io_read(1,idir,'vz',ext,planio,R1)
      CALL fftp2d_real_to_complex(planrc,R1,vz,MPI_COMM_WORLD)
#endif
#endif
#ifdef VECPOT_
      CALL io_read(1,idir,'az',ext,planio,R1)
      CALL fftp2d_real_to_complex(planrc,R1,az,MPI_COMM_WORLD)
#ifdef D25_
      CALL io_read(1,idir,'bz',ext,planio,R1)
      CALL fftp2d_real_to_complex(planrc,R1,bz,MPI_COMM_WORLD)
#endif
#endif

      ENDIF IC

!
! Time integration scheme starts here.
! Does ord iterations of Runge-Kutta. If 
! we are doing a benchmark, we measure 
! cputime before starting.

      IF (bench.eq.1) THEN
         CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
         CALL CPU_Time(cputime1)
      ENDIF

 RK : DO t = ini,step

! Updates the external forcing. Every 'fsteps'
! the phase is changed according to the value
! of 'rand'.

         IF (timef.eq.fstep) THEN
            timef = 0

            IF (rand.eq.1) THEN      ! randomizes phases

               IF (myrank.eq.0) phase = 2*pi*randu(seed)
               CALL MPI_BCAST(phase,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
               cdump = COS(phase)+im*SIN(phase)
               jdump = conjg(cdump)
#ifdef MAGFIELD_
               IF (myrank.eq.0) phase = 2*pi*randu(seed)
               CALL MPI_BCAST(phase,1,GC_REAL,0,MPI_COMM_WORLD,ierr)
               cdumq = corr*cdump+(1-corr)*(COS(phase)+im*SIN(phase))
               jdumq = corr*jdump+(1-corr)*conjg(cdump)
#endif
               IF (ista.eq.1) THEN
                  DO j = 2,n/2+1
#ifdef STREAM_
                     fk(j,1) = fk(j,1)*cdump
                     fk(n-j+2,1) = fk(n-j+2,1)*jdump
#ifdef D25_
                     fz(j,1) = fz(j,1)*cdump
                     fz(n-j+2,1) = fz(n-j+2,1)*jdump
#endif
#endif
#ifdef VECPOT_
                     mk(j,1) = mk(j,1)*cdumq
                     mk(n-j+2,1) = mk(n-j+2,1)*jdumq
#ifdef D25_
                     mz(j,1) = mz(j,1)*cdump
                     mz(n-j+2,1) = mz(n-j+2,1)*jdump
#endif
#endif
                  END DO
                  DO i = 2,iend
                     DO j = 1,n
#ifdef STREAM_
                        fk(j,i) = fk(j,i)*cdump
#ifdef D25_
                        fz(j,i) = fz(j,i)*cdump
#endif
#endif
#ifdef VECPOT_
                        mk(j,i) = mk(j,i)*cdumq
#ifdef D25_
                        mz(j,i) = mz(j,i)*cdump
#endif
#endif
                     END DO
                  END DO
               ELSE
                  DO i = ista,iend
                     DO j = 1,n
#ifdef STREAM_
                        fk(j,i) = fk(j,i)*cdump
#ifdef D25_
                        fz(j,i) = fz(j,i)*cdump
#endif
#endif
#ifdef VECPOT_
                        mk(j,i) = mk(j,i)*cdumq
#ifdef D25_
                        mz(j,i) = mz(j,i)*cdump
#endif
#endif
                     END DO
                  END DO
               ENDIF

            ENDIF

         ENDIF

! Every 'tstep' steps, stores the fields 
! in binary files

         IF ((timet.eq.tstep).and.(bench.eq.0)) THEN
            timet = 0
            tind = tind+1
            rmp = 1./real(n,kind=GP)**2
#ifdef STREAM_
            DO i = ista,iend
               DO j = 1,n
                  C1(j,i) = ps(j,i)*rmp
               END DO
            END DO
            IF (outs.ge.1) THEN
               CALL laplak2(C1,C2)
               CALL fftp2d_complex_to_real(plancr,C2,R1,MPI_COMM_WORLD)
               CALL io_write(1,odir,'wz',ext,planio,R1)
            ENDIF
            CALL fftp2d_complex_to_real(plancr,C1,R1,MPI_COMM_WORLD)
            CALL io_write(1,odir,'ps',ext,planio,R1)
#ifdef D25_
            DO i = ista,iend
               DO j = 1,n
                  C1(j,i) = vz(j,i)*rmp
               END DO
            END DO
            CALL fftp2d_complex_to_real(plancr,C1,R1,MPI_COMM_WORLD)
            CALL io_write(1,odir,'vz',ext,planio,R1)
#endif
#endif
#ifdef VECPOT_
            DO i = ista,iend
               DO j = 1,n
                  C1(j,i) = az(j,i)*rmp
               END DO
            END DO
            IF (outs.ge.1) THEN
               CALL laplak2(C1,C2)
               CALL fftp2d_complex_to_real(plancr,C2,R1,MPI_COMM_WORLD)
               CALL io_write(1,odir,'jz',ext,planio,R1)
            ENDIF
            CALL fftp2d_complex_to_real(plancr,C1,R1,MPI_COMM_WORLD)
            CALL io_write(1,odir,'az',ext,planio,R1)
#ifdef D25_
            DO i = ista,iend
               DO j = 1,n
                  C1(j,i) = bz(j,i)*rmp
               END DO
            END DO
            CALL fftp2d_complex_to_real(plancr,C1,R1,MPI_COMM_WORLD)
            CALL io_write(1,odir,'bz',ext,planio,R1)
#endif
#endif
         ENDIF

! Every 'cstep' steps, generates external files 
! with global quantities.

         IF ((timec.eq.cstep).and.(bench.eq.0)) THEN
            timec = 0
#ifdef HD_SOL
            INCLUDE 'hd_global.f90'
#endif
#ifdef MHD_SOL
            INCLUDE 'mhd_global.f90'
#endif
#ifdef MHDB_SOL
            INCLUDE 'mhd_global.f90'
#endif
#ifdef HMHD_SOL
            INCLUDE 'hmhd_global.f90'
#endif
         ENDIF

! Every 'sstep' steps, generates external files 
! with the power spectrum.

         IF ((times.eq.sstep).and.(bench.eq.0)) THEN
            times = 0
            sind = sind+1
            WRITE(ext, fmtext) sind
#ifdef HD_SOL
            INCLUDE 'hd_spectrum.f90'
#endif
#ifdef MHD_SOL
            INCLUDE 'mhd_spectrum.f90'
#endif
#ifdef MHDB_SOL
            INCLUDE 'mhd_spectrum.f90'
#endif
#ifdef HMHD_SOL
            INCLUDE 'hmhd_spectrum.f90'
#endif
         ENDIF

! Runge-Kutta step 1
! Copies the fields into auxiliary arrays

         DO i = ista,iend
         DO j = 1,n

#ifdef HD_SOL
         INCLUDE 'hd_rkstep1.f90'
#endif
#ifdef MHD_SOL
         INCLUDE 'mhd_rkstep1.f90'
#endif
#ifdef MHDB_SOL
         INCLUDE 'mhd_rkstep1.f90'
#endif
#ifdef HMHD_SOL
         INCLUDE 'hmhd_rkstep1.f90'
#endif

         END DO
         END DO

! Runge-Kutta step 2
! Evolves the system in time

         DO o = ord,1,-1
#ifdef HD_SOL
         INCLUDE 'hd_rkstep2.f90'
#endif
#ifdef MHD_SOL
         INCLUDE 'mhd_rkstep2.f90'
#endif
#ifdef MHDB_SOL
         INCLUDE 'mhdb_rkstep2.f90'
#endif
#ifdef HMHD_SOL
         INCLUDE 'hmhd_rkstep2.f90'
#endif
         END DO

         timet = timet+1
         times = times+1
         timec = timec+1
         timef = timef+1

      END DO RK

!
! End of Runge-Kutta

! Computes the benchmark

      IF (bench.eq.1) THEN
         CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
         CALL CPU_Time(cputime2)
         IF (myrank.eq.0) THEN
            OPEN(1,file='benchmark.txt',position='append')
            WRITE(1,*) n,(step-ini+1),nprocs, &
                       (cputime2-cputime1)/(step-ini+1)
            CLOSE(1)
         ENDIF
      ENDIF
!
! End of MAIN2D

      CALL MPI_FINALIZE(ierr)
      CALL fftp2d_destroy_plan(plancr)
      CALL fftp2d_destroy_plan(planrc)
      DEALLOCATE( R1 )
      DEALLOCATE( C1,C2 )
      DEALLOCATE( ka,ka2 )
#ifdef STREAM_
      DEALLOCATE( ps,fk )
#ifdef D25_
      DEALLOCATE( vz,fz )
#endif
#endif
#ifdef VECPOT_
      DEALLOCATE( az,mk )
      DEALLOCATE( C3,C4,C5 )
      DEALLOCATE( R2 )
#ifdef D25_
      DEALLOCATE( bz,mz )
#endif
#endif
#ifdef HALLTERM_
      DEALLOCATE( C6,C7,C8,C9,C10,C11 )
#endif

      END PROGRAM MAIN2D
