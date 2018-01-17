MODULE mc_grids
  !
  USE q_grids
#include "mpi_thermal.h"

  REAL(DP),PRIVATE :: avg_npoints = 0._dp, avg_tested_npoints = 0._dp, saved_threshold
  INTEGER,PRIVATE  :: ngrids_optimized

  CONTAINS
  !
  SUBROUTINE setup_mcjdos_grid(input, S, fc, grid, xq0, nq_target, scatter)
    USE code_input,       ONLY : code_input_type
    USE input_fc,         ONLY : ph_system_info, forceconst2_grid
    USE ph_dos,           ONLY : joint_dos_q
    USE random_numbers,   ONLY : randy
    USE constants,        ONLY : RY_TO_CMM1
    USE mpi_thermal
    IMPLICIT NONE
    TYPE(code_input_type),INTENT(in)  :: input
    TYPE(forceconst2_grid),INTENT(in) :: fc
    TYPE(ph_system_info),INTENT(in)   :: S
    !CHARACTER(len=*),INTENT(in)     :: grid_type
    !REAL(DP),INTENT(in)   :: bg(3,3) ! = System
    !INTEGER,INTENT(in) :: n1,n2,n3
    INTEGER,INTENT(in) :: nq_target
    TYPE(q_grid),INTENT(inout) :: grid
    REAL(DP),OPTIONAl,INTENT(in) :: xq0(3)
    LOGICAL,OPTIONAL,INTENT(in) :: scatter
    !
    REAL(DP) :: sigma_ry, avg_T
    !
    REAL(DP) :: xq_new(3), jdq_new, jdq_old
    INTEGER :: nq, iq
    LOGICAL :: accepted
    REAL(DP) :: acceptance, test
    TYPE(q_grid) :: grid0
    INTEGER :: warm_up

    !nq_target = 125
    warm_up = MIN(MAX(nq_target/10, 20), 100)
    nq = 1-warm_up
    jdq_old = -1._dp
    grid%type = 'mcjdos'

    sigma_ry = SUM(input%sigma)/RY_TO_CMM1/input%nconf
    avg_T = SUM(input%T)/input%nconf
    !print*, sigma_ry, avg_T

    ALLOCATE(grid%xq(3,nq_target))
    ALLOCATE(grid%w(nq_target))
    grid%scattered = .false.
    grid%nq    = nq_target
    grid%nqtot = nq_target

    CALL setup_grid("simple", S%bg, input%nk(1),input%nk(2),input%nk(3), &
                grid0, scatter=.true.)

    POPULATE_GRID : &
    DO
      xq_new = 0._dp
      IF(ionode)THEN
        IF(input%nk(1)>1) xq_new(1) = randy()/DBLE(input%nk(1))
        IF(input%nk(2)>1) xq_new(2) = randy()/DBLE(input%nk(2))
        IF(input%nk(3)>1) xq_new(3) = randy()/DBLE(input%nk(3))
        CALL cryst_to_cart(1,xq_new,S%bg, +1)
        test = randy()
      ENDIF
      CALL mpi_bcast_vec(3,xq_new)
      CALL mpi_bcast_scl(test)
      !
      jdq_new = 1._dp !joint_dos_q(grid0,sigma_ry,avg_T, S, fc, xq_new)
      !
      IF(jdq_old<=0._dp)THEN
        accepted = .true.
      ELSE
        acceptance = jdq_new/jdq_old
        accepted = (test <= acceptance)
      ENDIF
      !
      IF(accepted)THEN
        nq = nq+1
        jdq_old = jdq_new
        IF(nq>0)THEN
          grid%w(nq) = 1._dp
          grid%xq(:,nq) = xq_new
        ENDIF
        !ioWRITE(*,*) "accepted", nq, acceptance, jdq_old
      ELSE
        !ioWRITE(*,*) "discarded"
        IF(nq>0) grid%w(nq) = grid%w(nq)+1
      ENDIF
      !
      IF(nq==nq_target) EXIT POPULATE_GRID
      !
    ENDDO &
    POPULATE_GRID

    grid%w = 1._dp/grid%w
    grid%w = grid%w/SUM(grid%w)

    ioWRITE(7778,'(2x,"Setup a ",a," grid of",i9," q-points")') "mcjdos", grid%nqtot
    DO iq = 1,grid%nqtot
      ioWRITE(7778,'(3f12.6,f12.6)') grid%xq(:,iq), grid%w(iq)*grid%nqtot
    ENDDO
    IF(scatter) CALL grid%scatter()
    !
  END SUBROUTINE setup_mcjdos_grid



  SUBROUTINE setup_optimized_grid(input, S, fc, grid, xq0, prec, scatter)
    USE code_input,       ONLY : code_input_type
    USE input_fc,         ONLY : ph_system_info, forceconst2_grid
    USE ph_dos,           ONLY : joint_dos_q
    USE random_numbers,   ONLY : randy
    USE constants,        ONLY : RY_TO_CMM1
    USE fc2_interpolate,  ONLY : freq_phq_safe, set_nu0, bose_phq
    USE functions,        ONLY : bubble_sort_idx, quicksort_idx
    USE linewidth,        ONLY : sum_linewidth_modes
    USE mpi_thermal
    USE timers
    IMPLICIT NONE
    TYPE(code_input_type),INTENT(in)  :: input
    TYPE(forceconst2_grid),INTENT(in) :: fc
    TYPE(ph_system_info),INTENT(in)   :: S
    TYPE(q_grid),INTENT(inout) :: grid
    REAL(DP),INTENT(in) :: xq0(3)
    REAL(DP),INTENT(in) :: prec
    LOGICAL,INTENT(in) :: scatter
    !
    !
    TYPE(q_grid) :: grid0
    INTEGER :: iq, jq, nu0(3)
    REAL(DP) :: xq(3,3), totfklw, partialfklw, targetfklw
    REAL(DP),ALLOCATABLE :: V3sq(:,:,:), contributions(:), freq(:,:), bose(:,:), fklw(:)
    COMPLEX(DP),ALLOCATABLE :: U(:,:,:)
    INTEGER,ALLOCATABLE  :: idx(:)

    CALL t_optimize%start()

    grid%type = 'optimized'
    grid%scattered = .false.

    CALL setup_grid(input%grid_type, S%bg, input%nk(1), input%nk(2), input%nk(3), grid0, &
                    xq0=input%xk0, scatter=.false., quiet=.true.)
    !CALL setup_grid("simple", S%bg, input%nk(1),input%nk(2),input%nk(3), &
    !            grid0, scatter=.false.)

    ALLOCATE(contributions(grid0%nq))
    ALLOCATE(V3sq(S%nat3, S%nat3, S%nat3))
    ALLOCATE(U(S%nat3, S%nat3, 3))
    ALLOCATE(freq(S%nat3, 3))
    ALLOCATE(bose(S%nat3, 3))
    ALLOCATE(fklw(S%nat3))
    V3sq = 1._dp
    xq(:,1) = xq0
    nu0(1)  = set_nu0(xq(:,1), S%at)
    CALL freq_phq_safe(xq(:,1), S, fc, freq(:,1), U(:,:,1))
    CALL bose_phq(input%T(1),S%nat3, freq(:,1), bose(:,1))

    DO iq = 1, grid0%nq

      xq(:,2) = grid0%xq(:,iq)
      xq(:,3) = -(xq(:,2)+xq(:,1))
      DO jq = 2,3
        nu0(jq) = set_nu0(xq(:,jq), S%at)
        CALL freq_phq_safe(xq(:,jq), S, fc, freq(:,jq), U(:,:,jq))
        CALL bose_phq(input%T(1),S%nat3, freq(:,jq), bose(:,jq))
      ENDDO

      fklw = sum_linewidth_modes(S, input%sigma(1)/RY_TO_CMM1, freq, bose, V3sq, nu0)
      contributions(iq) = SUM(ABS(fklw))
    ENDDO
    DEALLOCATE(V3sq, U, freq, bose, fklw)
    !
    totfklw = SUM(contributions)
    targetfklw = (1._dp-prec) * totfklw
    ALLOCATE(idx(grid0%nq))
    CALL t_sorting%start()
    !CALL bubble_sort_idx(contributions,idx)
    FORALL(iq=1:grid0%nq) idx(iq) = iq
    CALL quicksort_idx(contributions,idx, 1, grid0%nq)
    CALL t_sorting%stop()
    !
    partialfklw = 0._dp
    DO iq = 1,grid0%nq
      jq = grid0%nq-iq+1
      partialfklw = partialfklw + contributions(jq)
      !write(8888, '(3i6, 3e15.6)') iq, jq, idx(jq), partialfklw, totfklw, contributions(jq)
      IF(partialfklw>targetfklw) EXIT
    ENDDO
    DEALLOCATE(contributions)
    !
    WRITE(stdout,'(f8.2,f12.6)'), DBLE(iq)/grid0%nq*100, partialfklw/totfklw*100
    grid%nq = iq
    grid%nqtot = iq
    ALLOCATE(grid%xq(3,grid%nq))
    ALLOCATE(grid%w(grid%nq))
    ! set point from less important to more, to reduce roundoff errors
    DO iq = 1,grid%nq
      jq = grid0%nq-iq+1
      grid%xq(:,iq) = grid0%xq(:,idx(jq))
      grid%w(iq) = grid0%w(idx(jq))
    ENDDO
    ! 
    IF(scatter) CALL grid%scatter(quiet=.true.)

     avg_npoints = (avg_npoints*ngrids_optimized + grid%nq)/DBLE(ngrids_optimized+1)
     avg_tested_npoints = (avg_tested_npoints*ngrids_optimized + grid0%nq)/DBLE(ngrids_optimized+1)
     saved_threshold = input%optimize_grid_thr
     ngrids_optimized = ngrids_optimized+1

    CALL t_optimize%stop()

    !
  END SUBROUTINE setup_optimized_grid

  SUBROUTINE print_optimized_stats()
    IMPLICIT NONE
    IF(avg_tested_npoints<1._dp) RETURN

    ioWRITE(*,'(a)') "*** * Grid optimization statistics:"
    ioWRITE(*,'(2x," * ",a24," * ",f15.0," / ",f15.0," * ",a15," = ",f15.2," * ", a10, " = ", es10.0," *")') &
      "avg #points in grid:", avg_npoints, avg_tested_npoints, &
      "speedup (%)", 100*(1-avg_npoints/avg_tested_npoints), &
      "threshold", saved_threshold
  END SUBROUTINE

END MODULE mc_grids
