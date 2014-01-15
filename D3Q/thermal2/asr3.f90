!
! Copyright Lorenzo Paulatto, Giorgia Fugallo 2013 - released under the CeCILL licence v 2.1 
!   <http://www.cecill.info/licences/Licence_CeCILL_V2.1-fr.txt>
!
!
MODULE asr3_module
  USE kinds,    ONLY : DP
  TYPE forceconst3_ofRR
    REAL(DP),ALLOCATABLE :: F(:,:, :,:, :,:)
  ENDTYPE forceconst3_ofRR
  
  TYPE index_r_type
    ! list of R vectors, used only for acoustic sum rule
    INTEGER :: nR                    ! number of distinc R
    INTEGER,ALLOCATABLE :: nRi(:)    ! how many times each R appears
    INTEGER :: nRx                   ! maxval(nRi); nRi <= nRx
    INTEGER,ALLOCATABLE :: yR(:,:)   ! the list of distinct R
    INTEGER,ALLOCATABLE :: idR(:,:)  ! for each of the nR distinct R, the index
                                     ! of its nRi-th occurence in the global list
                                     ! yR(:, idR(1:nRi(1:nR2), 1:nR2) (padded with zeroes)
    INTEGER :: iRe0                  ! index of R = (0,0,0)                                    
    INTEGER,ALLOCATABLE :: idmR(:)   ! for each R, the index of -R
    INTEGER,ALLOCATABLE :: idRmR(:,:)! for each couple i,j=1,..nR
                                     ! index of R_i-R_j
  END TYPE
  
  INTEGER,SAVE :: iter = 1
  REAL(DP),PARAMETER :: eps  = 1.e-8_dp, eps2 = 1.e-16_dp
  REAL(DP),PARAMETER :: eps0 = 1.e-30_dp
  
  CONTAINS
  ! \/o\________\\\_________________________________________/^>
  SUBROUTINE index_R(nR0, R0, nR,nRx, nRi, R, idR, iRe0, idmR, idRmR)
    USE input_fc, ONLY : ph_system_info, forceconst3_grid
    IMPLICIT NONE
    INTEGER,INTENT(in) :: nR0, R0(3,nR0)
    !
    INTEGER,INTENT(out) :: nR                    ! number of distinc R
    INTEGER,ALLOCATABLE,INTENT(out) :: nRi(:)    ! how many times each R appears
    INTEGER,INTENT(out) :: nRx                   ! maxval(nRi); nRi <= nRx
    INTEGER,ALLOCATABLE,INTENT(out) :: R(:,:)    ! the list of distinct R
    INTEGER,ALLOCATABLE,INTENT(out) :: idR(:,:)  ! for each of the nR distinct R, the index
                                ! of its nRi-th occurence in the global list
                                ! yR(:, idR(1:nRi(1:nR2), 1:nR2) (padded with zeroes)
    INTEGER,ALLOCATABLE,INTENT(out) :: idmR(:)   ! for each of the nR, index of -R
    INTEGER,ALLOCATABLE,INTENT(out) :: idRmR(:,:)! for each couple i,j=1,..nR
                                                 ! index of R_i-R_j
    INTEGER,INTENT(out) :: iRe0                  ! index of R = (0,0,0)      
    !
    INTEGER :: i, j, k, kk
    INTEGER,ALLOCATABLE :: nRi_(:) ! how many times each R2,R3 appears
    INTEGER,ALLOCATABLE :: R_(:,:)
    !
    ALLOCATE(R_(3,nR0),nRi_(nR0))
    ! R0(:,1) is most likely (0 0 0) but this init it would work anyway
    nR = 1
    R_(:,1) = R0(:,1)
    nRi_ = 0
    !
    DO i = 1, nR0
      ! find the numebr of unique R and make a list of them
      j = find_index(nR, R_, R0(:,i))
      IF(j<0) THEN
        nR = nR+1
        j = nR
        R_(:,j) =  R0(:,i)
      ENDIF
      nRi_(j) =  nRi_(j) +1
    ENDDO
    !
    ALLOCATE(R(3,nR),nRi(nR))
    R(:,1:nR) = R_(:,1:nR)
    nRi(1:nR) = nRi_(1:nR)
    DEALLOCATE(R_, nRi_)
    
    nRx = MAXVAL(nRi)
    ALLOCATE(idR(nRx,nR))
    idR = 0
    !
    kk = 0
    DO j = 1,nR
      !
      k = 0
      DO i = 1, nR0
        IF ( ALL(R(:,j) == R0(:,i)) ) THEN
          k = k+1
          IF(k>nRi(j)) CALL errore("index_R", "too many r",1)
          idR(k,j) = i
        ENDIF
        IF( ALL(R(:,j) == 0)) iRe0 = j
      ENDDO
      kk = kk +k
      !
    ENDDO
    !
    ! Find -R for each R
    ALLOCATE(idmR(nR))
    idmR = -1
    DO j = 1,nR
    DO i = 1,nR
      IF ( ALL(R(:,i) == -R(:,j)) ) idmR(i) = j
    ENDDO
    ENDDO
    !
    ! Find R_k = R_i-R_j for each i and j
    ALLOCATE(idRmR(nR,nR))
    idRmR = -1
    DO k = 1,nR
    DO j = 1,nR
    DO i = 1,nR
      IF ( ALL(R(:,k) == R(:,i)-R(:,j)) ) idRmR(i,j) = k
    ENDDO
    ENDDO
    ENDDO
    !
    IF(kk/=nR0) CALL errore('index_R', "some r not found",2)
    !
    print*, "R ===================", nR, iRe0
    DO i = 1, nR
      WRITE(*,'(2i3,2x,3i3,2x,i3,2x,1000i5)') i,idmR(i), R(:,i), nRi(i), idR(1:nRi(i),i)
    ENDDO
    
  END SUBROUTINE
  ! \/o\________\\\_________________________________________/^>
  SUBROUTINE index_2R(idx2,idx3,fc,idR23)
    USE input_fc,       ONLY : forceconst3_grid
    IMPLICIT NONE
    !
    TYPE(index_r_type),INTENT(in) :: idx2, idx3
    TYPE(forceconst3_grid),INTENT(inout) :: fc
    INTEGER,INTENT(out),ALLOCATABLE :: idR23(:,:)
    INTEGER :: i2,i3, j
    
    ALLOCATE(idR23(idx2%nR,idx3%nR))
    idR23 = -1
    
    DO i2 = 1,idx2%nR
    DO i3 = 1,idx3%nR
      DO j = 1,fc%n_R
        IF(     ALL(idx2%yR(:,i2) == fc%yR2(:,j)) &
          .and. ALL(idx3%yR(:,i3) == fc%yR3(:,j)) ) THEN
          idR23(i2,i3) = j
          !WRITE(*,'(2i4,2x,2i4,2x,i4)') i2,i3, idR23(i2,i3)
        ENDIF
      ENDDO
      !WRITE(333,'(2i4,2x,2i4,2x,i4)') i2,i3, idR23(i2,i3)
    ENDDO
    ENDDO
    
  END SUBROUTINE index_2R
  ! \/o\________\\\_________________________________________/^>
  INTEGER FUNCTION find_index(n, list, item) RESULT(idR)
    IMPLICIT NONE
    INTEGER,INTENT(in) ::  n, list(3,n), item(3)
    DO idR = 1,n
      IF( ALL(list(:,idR) == item(:)) ) RETURN
    ENDDO
    idR = -1
  END FUNCTION
  ! \/o\________\\\_________________________________________/^>
  SUBROUTINE fc_3idx_2_6idx(nat, fc3, fc6, dir)
    USE kinds, ONLY : DP
    IMPLICIT NONE
    REAL(DP),INTENT(inout) :: fc3(3*nat, 3*nat, 3*nat)   ! d3 in cartesian basis
    REAL(DP),INTENT(inout) :: fc6(3,3,3, nat,nat,nat)    ! d3 in pattern basis
    INTEGER,INTENT(in) :: nat
    INTEGER,INTENT(in) :: dir
    !
    INTEGER :: i, j, k
    INTEGER :: at_i, at_j, at_k
    INTEGER :: pol_i, pol_j, pol_k
    !
    DO k = 1, 3*nat
      at_k  = 1 + (k-1)/3
      pol_k = k - 3*(at_k-1)
      !
      DO j = 1, 3*nat
        at_j  = 1 + (j-1)/3
        pol_j = j - 3*(at_j-1)
        !
        DO i = 1, 3*nat
          at_i  = 1 + (i-1)/3
          pol_i = i - 3*(at_i-1)
          !
          IF(dir > 0) THEN
            fc6(pol_i, pol_j, pol_k, at_i, at_j, at_k) &
              = fc3(i,j,k)
          ELSE IF( dir<0) THEN
            fc3(i,j,k) = &
                fc6(pol_i, pol_j, pol_k, at_i, at_j, at_k)
          ELSE
            CALL errore("fc_3idx_2_6idx","wrong dir",1)
          ENDIF
          !
        ENDDO
      ENDDO
    ENDDO
    !
    RETURN
  END SUBROUTINE fc_3idx_2_6idx
  ! \/o\________\\\_________________________________________/^>
  SUBROUTINE reindex_fc3(nat,fc,idR23,idx2,idx3,fx,dir)
    USE input_fc,       ONLY : forceconst3_grid
    IMPLICIT NONE
    !
    INTEGER,INTENT(in) :: nat, dir
    TYPE(forceconst3_grid),INTENT(inout) :: fc
    TYPE(index_r_type) :: idx2, idx3
    INTEGER,INTENT(in) :: idR23(idx2%nR,idx3%nR)
    TYPE(forceconst3_ofRR),INTENT(inout) :: fx(idx2%nR,idx3%nR)
    !
    INTEGER :: iR2,iR3

    IF(dir>0) THEN
        DO iR2 = 1,idx2%nR
        DO iR3 = 1,idx3%nR
          IF(.not.ALLOCATED(fx(iR2,iR3)%F)) &
            ALLOCATE(fx(iR2,iR3)%F(3,3,3,nat,nat,nat))
          fx(iR2,iR3)%F = 0._dp
        ENDDO
        ENDDO
    ELSE IF(dir<0) THEN
      IF(.not.ALLOCATED(fc%fc)) &
        ALLOCATE(fc%fc(3*nat,3*nat,3*nat, fc%n_R))
      fc%fc = 0._dp
    ELSE
          CALL errore("reindex_fc3","bad dir",1)
    ENDIF

    
    DO iR2 = 1,idx2%nR
    DO iR3 = 1,idx3%nR
      IF(idR23(iR2,iR3)>0) THEN
        CALL fc_3idx_2_6idx(nat, &
                            fc%fc(:,:,:,  idR23(iR2,iR3)), &
                            fx(iR2,iR3)%F, dir )
      
      ENDIF
    ENDDO
    ENDDO
    
  END SUBROUTINE reindex_fc3
  ! \/o\________\\\_________________________________________/^>
  ! symmetrize 3-body force constants wrt permutation of the indexes
  ! Note that the first R of the FC is always zero, hence we have to
  ! use translational symmetry, i.e.:
  ! F^3(R2,0,R3| b,a,c | j,i,k )  --> F^3(0,-R2,R3-R2| b,a,c | j,i,k )
  FUNCTION perm_symmetrize_fc3(nat,idx,fx) RESULT(delta)
    USE input_fc,       ONLY : forceconst3_grid
    IMPLICIT NONE
    !
    INTEGER,INTENT(in) :: nat
    TYPE(index_r_type) :: idx
    TYPE(forceconst3_ofRR),INTENT(inout) :: fx(idx%nR,idx%nR)
    !
    INTEGER :: iR2,iR3, a,b,c, i,j,k
    INTEGER :: mR2, mR3, iR2mR3, iR3mR2
    REAL(DP) :: avg, delta
    
    delta = 0._dp
    
    DO iR2 = 1,idx%nR
    R3_LOOP : &
    DO iR3 = 1,idx%nR
      mR2 = idx%idmR(iR2)
      mR3 = idx%idmR(iR3)
      !
      iR2mR3 = idx%idRmR(iR2,iR3)
      iR3mR2 = idx%idRmR(iR3,iR2)
      !
      IF(iR2mR3<0 .or. iR3mR2<0) THEN
        IF( ANY(ABS(fx(iR2,iR3)%F) > 1.e-24_dp) ) &
          CALL errore('impose_asr3', 'this should be zero', 1)
        fx(iR2,iR3)%F = 0._dp
        CYCLE R3_LOOP
      ENDIF
      !
      DO a = 1,3
      DO b = 1,3
      DO c = 1,3
        DO i = 1,nat
        DO j = 1,nat
        DO k = 1,nat
        
          avg = 1._dp/6._dp * ( &
                    fx(iR2,   iR3   )%F(a,b,c, i,j,k) &
                  + fx(iR3,   iR2   )%F(a,c,b, i,k,j) &
                  + fx(mR2,   iR3mR2)%F(b,a,c, j,i,k) &
                  + fx(iR3mR2,mR2   )%F(b,c,a, j,k,i) &
                  + fx(mR3,   iR2mR3)%F(c,a,b, k,i,j) &
                  + fx(iR2mR3,mR3   )%F(c,b,a, k,j,i) &
                  )

          delta = delta + (fx(iR2,iR3)%F(a,b,c, i,j,k) - avg)**2
          fx(iR2,iR3)%F(a,b,c, i,j,k) = avg

        
        ENDDO
        ENDDO
        ENDDO
      ENDDO
      ENDDO
      ENDDO
    ENDDO R3_LOOP
    ENDDO
    !
    delta = SQRT(delta)
!     WRITE(*,'(75x,a,f12.6)') "ps", SQRT(delta)
    !
  END FUNCTION perm_symmetrize_fc3
  ! \/o\________\\\_________________________________________/^>
  SUBROUTINE impose_asr3_6idx(nat,idx,fx)
    USE input_fc,       ONLY : forceconst3_grid
    IMPLICIT NONE
    !
    INTEGER,INTENT(in) :: nat
    TYPE(index_r_type) :: idx
    TYPE(forceconst3_ofRR),INTENT(inout) :: fx(idx%nR,idx%nR)
    !
    INTEGER :: iR2,iR3, a,b,c, i,j,k
    REAL(DP):: deltot, delsig, delperm
    REAL(DP):: d1,d2,d3,d4,d5,d6, q1,q2,q3,q4,q5,q6
    INTEGER :: mR2, mR3, iR2mR3, iR3mR2
    !
    deltot = 0._dp
    DO iR2 = 1,idx%nR
      !
      DO a = 1,3
      DO b = 1,3
      DO c = 1,3
        DO j = 1,nat
        DO k = 1,nat
          !
          ! The sum is on one R (it does not matter which)
          ! and the first atom index
          d1 = 0._dp; q1 = 0._dp
          d2 = 0._dp; q2 = 0._dp
          d3 = 0._dp; q3 = 0._dp
          d4 = 0._dp; q4 = 0._dp
          d5 = 0._dp; q5 = 0._dp
          d6 = 0._dp; q6 = 0._dp
          R3_LOOP : &
          DO iR3 = 1,idx%nR
          DO i = 1,nat
              mR2 = idx%idmR(iR2)
              mR3 = idx%idmR(iR3)
              !
              iR2mR3 = idx%idRmR(iR2,iR3)
              iR3mR2 = idx%idRmR(iR3,iR2)
              !
              IF(iR2mR3<0 .or. iR3mR2<0) THEN
                IF( ANY(fx(iR2,iR3)%F > eps0) ) &
                  CALL errore("asr6","missing bits",1)
                CYCLE R3_LOOP
              ENDIF
              d1 = d1 + fx(iR2,   iR3   )%F(a,b,c, i,j,k)
              q1 = q1 + fx(iR2,   iR3   )%F(a,b,c, i,j,k)**2
                                      
              d2 = d2 + fx(iR3,   iR2   )%F(a,c,b, i,k,j)
              q2 = q2 + fx(iR3,   iR2   )%F(a,c,b, i,k,j)**2
                                      
              d3 = d3 + fx(mR2,   iR3mR2)%F(b,a,c, j,i,k)
              q3 = q3 + fx(mR2,   iR3mR2)%F(b,a,c, j,i,k)**2
                                      
              d4 = d4 + fx(iR3mR2,mR2   )%F(b,c,a, j,k,i)
              q4 = q4 + fx(iR3mR2,mR2   )%F(b,c,a, j,k,i)**2
                                      
              d5 = d5 + fx(mR3,   iR2mR3)%F(c,a,b, k,i,j)
              q5 = q5 + fx(mR3,   iR2mR3)%F(c,a,b, k,i,j)**2
                                      
              d6 = d6 + fx(iR2mR3,mR3   )%F(c,b,a, k,j,i)
              q6 = q6 + fx(iR2mR3,mR3   )%F(c,b,a, k,j,i)**2
          ENDDO
          ENDDO R3_LOOP
          !
          deltot = deltot + SUM( (/d1,d2,d3,d4,d5,d5/)**2 )
          delsig = delsig + SUM( (/d1,d2,d3,d4,d5,d5/) )
          
!           d1 = (d1+d2+d3+d4+d5+d6)/6._dp
!           q1 = (q1+q2+q3+q4+q5+q6)/6._dp
!           d2=d1; d3=d1; d4=d1; d5=d1; d6=d1
!           q2=q1; q3=q1; q4=q1; q5=q1; q6=q1
          !
          R3_LOOPb : &
          DO iR3 = 1,idx%nR
            !
            mR2 = idx%idmR(iR2)
            mR3 = idx%idmR(iR3)
            !
            iR2mR3 = idx%idRmR(iR2,iR3)
            iR3mR2 = idx%idRmR(iR3,iR2)
            !
            IF(iR2mR3<0 .or. iR3mR2<0) THEN
              IF( ANY(fx(iR2,iR3)%F > eps0) ) &
                CALL errore("asr6","missing bits",2)
              CYCLE R3_LOOPb
            ENDIF
            !
            DO i = 1,nat

              IF(ABS(q1)>eps2 .and. ABS(d1)>eps &
                 .and. ABS(fx(iR2,   iR3   )%F(a,b,c, i,j,k))>eps ) &
              fx(iR2,   iR3   )%F(a,b,c, i,j,k) = fx(iR2,   iR3   )%F(a,b,c, i,j,k) &
                                        - d1/q1 * fx(iR2,   iR3   )%F(a,b,c, i,j,k)**2
                                      
              IF(ABS(q2)>eps2 .and. ABS(d2)>eps &
                 .and. ABS(fx(iR3,   iR2   )%F(a,c,b, i,k,j))>eps ) &
              fx(iR3,   iR2   )%F(a,c,b, i,k,j) = fx(iR3,   iR2   )%F(a,c,b, i,k,j) &
                                        - d2/q2 * fx(iR3,   iR2   )%F(a,c,b, i,k,j)**2
                                      
              IF(ABS(q3)>eps2 .and. ABS(d3)>eps &
                 .and. ABS(fx(mR2,   iR3mR2)%F(b,a,c, j,i,k))>eps ) &
              fx(mR2,   iR3mR2)%F(b,a,c, j,i,k) = fx(mR2,   iR3mR2)%F(b,a,c, j,i,k) &
                                        - d3/q3 * fx(mR2,   iR3mR2)%F(b,a,c, j,i,k)**2
                                      
              IF(ABS(q4)>eps2 .and. ABS(d4)>eps &
                 .and. ABS(fx(iR3mR2,mR2   )%F(b,c,a, j,k,i))>eps ) &
              fx(iR3mR2,mR2   )%F(b,c,a, j,k,i) = fx(iR3mR2,mR2   )%F(b,c,a, j,k,i) &
                                        - d4/q4 * fx(iR3mR2,mR2   )%F(b,c,a, j,k,i)**2

              IF(ABS(q5)>eps2 .and. ABS(d5)>eps &
                 .and. ABS(fx(mR3,   iR2mR3)%F(c,a,b, k,i,j))>eps ) &
              fx(mR3,   iR2mR3)%F(c,a,b, k,i,j) = fx(mR3,   iR2mR3)%F(c,a,b, k,i,j) &
                                        - d5/q5 * fx(mR3,   iR2mR3)%F(c,a,b, k,i,j)**2
                                      
              IF(ABS(q6)>eps2 .and. ABS(d6)>eps &
                 .and. ABS(fx(iR2mR3,mR3   )%F(c,b,a, k,j,i))>eps ) &
              fx(iR2mR3,mR3   )%F(c,b,a, k,j,i) = fx(iR2mR3,mR3   )%F(c,b,a, k,j,i) &
                                        - d6/q6 * fx(iR2mR3,mR3   )%F(c,b,a, k,j,i)**2
            ENDDO
          ENDDO R3_LOOPb
          !
        ENDDO
        ENDDO
      ENDDO
      ENDDO
      ENDDO
    ENDDO
    !
    delperm = perm_symmetrize_fc3(nat,idx,fx)
    PRINT*, "asr6", iter, SQRT(deltot), SQRT(ABS(deltot-delsig**2)), delperm
    iter = iter+1
    !
  END SUBROUTINE impose_asr3_6idx
  ! \/o\________\\\_________________________________________/^>
  SUBROUTINE impose_asr3_1idx(nat,idx,fx)
    USE input_fc,       ONLY : forceconst3_grid
    IMPLICIT NONE
    !
    INTEGER,INTENT(in) :: nat
    TYPE(index_r_type) :: idx
    TYPE(forceconst3_ofRR),INTENT(inout) :: fx(idx%nR,idx%nR)
    !
    INTEGER :: iR2,iR3, a,b,c, i,j,k
    REAL(DP):: deltot, delsig, delperm
    REAL(DP):: d1, q1, r1
    !
    deltot = 0._dp
    DO iR2 = 1,idx%nR
      !
      DO a = 1,3
      DO b = 1,3
      DO c = 1,3
        DO j = 1,nat
        DO k = 1,nat
          !
          ! The sum is on one R (it does not matter which)
          ! and the first atom index
          d1 = 0._dp
          q1 = 0._dp
          R3_LOOP : &
          DO iR3 = 1,idx%nR
          DO i = 1,nat
              d1 = d1+fx(iR2,   iR3   )%F(a,b,c, i,j,k)
              q1 = q1+fx(iR2,   iR3   )%F(a,b,c, i,j,k)**2
          ENDDO
          ENDDO R3_LOOP
          !
          deltot = deltot + d1**2
          delsig = delsig + d1
          !
          r1 = d1/q1
          IF(ABS(d1) >eps .and. ABS(q1)>eps2) THEN
            !
            R3_LOOPb : &
            DO iR3 = 1,idx%nR
            DO i = 1,nat
                IF( ABS(fx(iR2,iR3)%F(a,b,c, i,j,k))>eps0 ) &
                fx(iR2,iR3)%F(a,b,c, i,j,k) = fx(iR2,iR3)%F(a,b,c, i,j,k) &
                                       - r1 * fx(iR2,iR3)%F(a,b,c, i,j,k)**2
            ENDDO
            ENDDO R3_LOOPb
            !
          ENDIF
          !
        ENDDO
        ENDDO
      ENDDO
      ENDDO
      ENDDO
    ENDDO
    !
    ! Re-symmetrize the matrix
    delperm = perm_symmetrize_fc3(nat,idx,fx)
    !
    PRINT*, "asr3", iter, SQRT(deltot), SQRT(ABS(deltot-delsig**2)), delperm
    !
    iter = iter+1
    !
  END SUBROUTINE impose_asr3_1idx
  ! \/o\________\\\_________________________________________/^>

END MODULE asr3_module


!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!
PROGRAM asr3

    USE kinds,          ONLY : DP
    USE iso_c_binding,  ONLY : c_int
    USE input_fc,       ONLY : read_fc3, aux_system,  write_fc3, &
                               forceconst3_grid, ph_system_info
    USE io_global,      ONLY : stdout
    USE asr3_module
    IMPLICIT NONE
    !
    TYPE(forceconst3_grid) :: fc
    TYPE(ph_system_info)   :: s
    TYPE(index_r_type)     :: idx2,idx3
    INTEGER(kind=c_int)    :: kb
    INTEGER,ALLOCATABLE :: idR23(:,:)
    TYPE(forceconst3_ofRR),ALLOCATABLE :: fx(:,:)
    !
    INTEGER :: j
    REAL(DP) :: delta
    !
    CALL read_fc3("mat3R", S, fc)
    CALL aux_system(s)
    !
    CALL memstat(kb)
    WRITE(stdout,*) "Reading : done. //  Mem used:", kb/1000, "Mb"
    !
    CALL index_R(fc%n_R, fc%yR2, idx2%nR, idx2%nRx, idx2%nRi, &
                 idx2%yR, idx2%idR, idx2%iRe0, idx2%idmR, idx2%idRmR)
    !
    CALL index_R(fc%n_R, fc%yR2, idx3%nR, idx3%nRx, idx3%nRi, &
                 idx3%yR, idx3%idR, idx3%iRe0, idx3%idmR, idx3%idRmR)
    !
    ! Check that indeces are identical, this is not strictly necessary, 
    ! but it makes the rest easier
    IF(idx2%nR/=idx3%nR .or. ANY(idx2%yR/=idx3%yR) )&
      CALL errore("asr3", "problem with R",1)
    IF(ANY(idx2%idmR/=idx3%idmR))&
      CALL errore("asr3", "problem with -R",2)
    IF(ANY(idx2%idRmR/=idx3%idRmR))&
      CALL errore("asr3", "problem with R-R",3)
    !
    CALL index_2R(idx2,idx3, fc, idR23)
    
    CALL memstat(kb)
    WRITE(stdout,*) "R indexing : done. //  Mem used:", kb/1000, "Mb"
    !
    ALLOCATE(fx(idx2%nR, idx3%nR))

    CALL reindex_fc3(S%nat,fc,idR23,idx2,idx3,fx,+1)
    CALL memstat(kb)
    WRITE(stdout,*) "FC3 reindex : done. //  Mem used:", kb/1000, "Mb"

!     write(333, '(1i6)') idR23
    
    DO j =1,10
      CALL impose_asr3_6idx(S%nat,idx2,fx)
!       delta = perm_symmetrize_fc3(S%nat,idx2,fx)
    ENDDO

!    DO j = 1,2000
!      CALL impose_asr3_1idx(S%nat,idx2,fx)
!    ENDDO
!     !
    CALL memstat(kb)
    WRITE(stdout,*) "Impose asr3 : done. //  Mem used:", kb/1000, "Mb"

    CALL reindex_fc3(S%nat,fc,idR23,idx2,idx3,fx,-1)

    CALL write_fc3("mat3R_asr", S, fc)
    !
END PROGRAM asr3
!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!












