!
! programmino di esempio...
!
PROGRAM read3
  USE kinds,       ONLY : DP
  USE d3matrix_io, ONLY : read_d3dyn_xml
  use cell_base,       ONLY : at, ibrav, celldm, omega
  USE parameters, ONLY : ntypx

  IMPLICIT NONE
  REAL(DP) :: xq1(3), xq2(3), xq3(3), maxdiff, amass(ntypx)
  COMPLEX(DP),ALLOCATABLE :: p3(:,:,:, :,:,:), q3(:,:,:, :,:,:)
  INTEGER,ALLOCATABLE :: ityp(:)
  REAL(DP),ALLOCATABLE :: tau(:,:)
  CHARACTER(len=256) :: fname1, title
  INTEGER :: nat, i,j,k,a,b,c, ios, ntyp, nt, na, icar, ic,jc
  LOGICAL :: found, first
  INTEGER,PARAMETER :: iudyn = 666
  CHARACTER(LEN=3) :: atm(ntypx)
  !
  title="bogus title"
  first=.true.
  !
  OPEN(unit=iudyn, file="d3.txt", status='unknown')
  FILES_LOOP : &
  DO WHILE(.true.)
    READ(*,'(a256)',iostat=ios) fname1   ! <-- the first one is the full file (e.g. anh_Q1.0_0_0_Q2.0_0_0_Q3.0_0_0)
    IF(ios/=0 .or. trim(fname1) == ' ') EXIT FILES_LOOP
    WRITE(*,*) "reading file... '"//TRIM(fname1)//"'"
    !
    !CALL read_d3dyn_xml(fname1, d3=p3, nat=nat)
    !CALL read_d3dyn_xml(fname2, d3=q3)
    IF(first)THEN
      write(iudyn, "('Generated by xml2giorgia.x')")
      write(iudyn, "('one bogus empty line...')")
      first=.false.
      CALL read_d3dyn_xml(fname1, xq1, xq2, xq3, d3=p3, nat=nat, atm=atm, ntyp=ntyp, &
                          ityp=ityp, ibrav=ibrav, celldm=celldm, at=at, amass=amass,&
                          tau=tau)
      CALL latgen( ibrav, celldm, at(:,1), at(:,2), at(:,3), omega )
      at=at/celldm(1)
      !
!       write (iudyn, '("Derivative of the force constants")')
!       write (iudyn, '(a)') title
      write (iudyn, '(i3,i5,i3,6f11.7)') ntyp, nat, ibrav, celldm
      if(ibrav==0)then
         write (iudyn, '(5x,3f20.12)'  ) ((at(ic,jc),ic=1,3),jc=1,3)
      endif
      do nt = 1, ntyp
        write (iudyn, * ) nt, " '", atm (nt) , "' ", amass (nt)
      enddo
      do na = 1, nat
        write (iudyn, '(2i5,3f15.7)') na, ityp (na) , (tau (j, na) , j = &
              1, 3)
      enddo
      write (iudyn, "(/,5x,'Third derivative in cartesian axes')")
    ELSE
      CALL read_d3dyn_xml(fname1, xq1, xq2, xq3, d3=p3)
    ENDIF
    !
    write (iudyn,*)
    write (iudyn, "(' q1= ',3f14.9)") (xq1(icar), icar = 1, 3)
    write (iudyn, "(' q2= ',3f14.9)") (xq2(icar), icar = 1, 3)
    write (iudyn, "(' q3= ',3f14.9)") (xq3(icar), icar = 1, 3)
    write (iudyn,*)
    !
    !
    DO c = 1,nat
      DO b = 1,nat
        DO a = 1,nat
    DO k = 1,3
      DO j = 1,3
        DO i = 1,3
          write(iudyn, '(3(2i3),2e28.15)') &
                i,a, j,b, k,c, &
                p3(i,j,k,a,b,c)
        ENDDO
        ENDDO
      ENDDO
      ENDDO
    ENDDO
    ENDDO

  END DO &
  FILES_LOOP
  !
  close(iudyn)
  !
END PROGRAM read3


