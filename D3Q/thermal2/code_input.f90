!
! Written by Lorenzo Paulatto (2015) IMPMC @ UPMC / CNRS UMR7590
!  released under the CeCILL licence v 2.1
!  <http://www.cecill.info/licences/Licence_CeCILL_V2.1-fr.txt>
!
! <<^V^\\=========================================//-//-//========//O\\//
! This module is a big mess that read input and check if there are no conflicts
MODULE code_input
  USE kinds,    ONLY : DP
  REAL(DP) :: default_sigma = 10._dp
  
  ! NOTE: energies in the LWINPUT_TYPE structure are assumed to be in CM^-1
  !       in the rest of the code energies are in Rydberg!
  TYPE code_input_type
    !
    CHARACTER(len=16) :: calculation ! lw=linewidth, spf=spectral function
    CHARACTER(len=16) :: mode        ! "full" or "simple" spectral function 
    CHARACTER(len=256) :: outdir
    CHARACTER(len=256) :: prefix     ! put this in fron of file names
    !
    LOGICAL :: exp_t_factor
    !
    CHARACTER(len=256) :: file_mat3
    CHARACTER(len=256) :: file_mat2
    LOGICAL            :: asr2
    !
    INTEGER            :: nconf
    REAL(DP),ALLOCATABLE :: T(:), sigma(:)
    ! for spectral function:
    INTEGER :: ne
    REAL(DP) :: e0, de
    ! for final state:
    REAL(DP) :: e_initial
    REAL(DP) :: q_initial(3)
    LOGICAL  :: q_resolved
    REAL(DP) :: sigmaq
    ! for isotope contribution to lw
    LOGICAL  :: isotopic_disorder
    ! for border scattering, grain size effects
    LOGICAL  :: casimir_scattering
    ! NOTE: Casimir length must also include the structure factor (usually 0.5)
    REAL(DP) :: casimir_length
    REAL(DP) :: casimir_dir(3)
    !
    INTEGER :: nk(3)
  END TYPE code_input_type
  !
  CONTAINS
  !
  ! read everything from files mat2R and mat3R
  SUBROUTINE READ_INPUT(code, input, qpts, S, fc2, fc3)
    USE io_global,      ONLY : stdout
    USE q_grid,         ONLY : q_grid_type, setup_path, setup_simple_grid
    USE constants,      ONLY : RY_TO_CMM1, BOHR_RADIUS_SI
    USE more_constants, ONLY : INVALID, MASS_DALTON_TO_RY
    USE wrappers,       ONLY : f_mkdir_safe
    USE fc3_interpolate,ONLY : forceconst3
    USE nist_isotopes_db, ONLY : compute_gs
    USE input_fc,       ONLY : div_mass_fc2, forceconst2_grid, ph_system_info
    !
    IMPLICIT NONE
    !
    CHARACTER(len=*),INTENT(in)    :: code
    TYPE(code_input_type),INTENT(out) :: input
    TYPE(q_grid_type),INTENT(out)  :: qpts
    TYPE(forceconst2_grid),INTENT(out) :: fc2
    CLASS(forceconst3),POINTER,INTENT(inout) :: fc3
    TYPE(ph_system_info),INTENT(out)   :: S
    !
    ! Input variable, and defaul values:
    CHARACTER(len=16)  :: calculation = "lw" ! "spf"
    CHARACTER(len=256) :: file_mat3  = INVALID ! no default
    CHARACTER(len=256) :: file_mat2  = INVALID ! no default
    CHARACTER(len=256) :: prefix     = INVALID ! default: calculation.mode
    !
    CHARACTER(len=256) :: outdir = './'
    LOGICAL            :: asr2 = .false.
    INTEGER            :: nconf = 1
    INTEGER            :: nq = -1
    INTEGER            :: nk(3) = (/-1, -1, -1/)
    LOGICAL            :: exp_t_factor = .false.
    !
    INTEGER  :: ne = -1
    REAL(DP) :: de = 1._dp, e0 = 0._dp
    REAL(DP) :: e_initial = -1._dp
    REAL(DP) :: q_initial(3) = 0._dp
    LOGICAL  :: q_resolved = .false.
    REAL(DP) :: sigmaq = 0.1_dp
    !
    LOGICAL  :: isotopic_disorder = .false.
    REAL(DP),ALLOCATABLE :: isotopes_mass(:), isotopes_conc(:), auxm(:), auxs(:)
    INTEGER :: n_isotopes, atomic_N
    !
    LOGICAL  :: casimir_scattering = .false.
    REAL(DP) :: casimir_length_au = -1._dp ! length in bohr
    REAL(DP) :: casimir_length_mu = -1._dp ! length in micrometres
    REAL(DP) :: casimir_length_mm = -1._dp ! length in millimitres
    REAL(DP) :: casimir_dir(3) = 0._dp
    !
    REAL(DP) :: xq(3), xq0(3)
    INTEGER  :: ios, ios2, i, j, naux, nq1, nq2, nq3
    CHARACTER(len=1024) :: line, word
    CHARACTER(len=16)   :: word2, word3
    CHARACTER(LEN=256), EXTERNAL :: TRIMCHECK
    CHARACTER (LEN=6), EXTERNAL :: int_to_char
    !
    LOGICAL :: qpoints_ok=.false., configs_ok=.false., isotopes_ok=.false.
    !
    NAMELIST  / lwinput / &
      calculation, outdir, prefix, &
      file_mat2, file_mat3, asr2, &
      nconf, nq, nk, &
      ne, de, e0, e_initial, q_initial, q_resolved, sigmaq, exp_t_factor, &
      isotopic_disorder, &
      casimir_scattering, casimir_length_au, casimir_length_mu, casimir_length_mm, casimir_dir

    NAMELIST  / tkinput / &
      calculation, outdir, prefix, &
      file_mat2, file_mat3, asr2, &
      nconf, nk, &
      isotopic_disorder, &
      casimir_scattering, casimir_length_au, casimir_length_mu, casimir_length_mm, casimir_dir


    WRITE(*,*) "Waiting for input"
    !
    IF(code=="LW")THEN
      READ(*, lwinput)
      WRITE(*, lwinput)
    ELSE IF (code=="TK")THEN
      READ(*, tkinput)
      WRITE(*, tkinput)
    ENDIF
    !
    IF(TRIM(file_mat2) == INVALID ) CALL errore('READ_INPUT', 'Missing file_mat2', 1)
    IF(TRIM(file_mat3) == INVALID ) CALL errore('READ_INPUT', 'Missing file_mat3', 1)
    IF(ANY(nk<0)) CALL errore('READ_INPUT', 'Missing nk', 1)    
    IF(nconf<0)   CALL errore('READ_INPUT', 'Missing nconf', 1)    
    
    input%file_mat2 = file_mat2
    input%file_mat3 = file_mat3
    input%outdir    = TRIMCHECK(outdir)
    input%asr2      = asr2
    input%nconf     = nconf
    input%nk        = nk
    input%exp_t_factor = exp_t_factor
    !
    input%isotopic_disorder  = isotopic_disorder
    input%casimir_scattering = casimir_scattering
    input%casimir_dir        = input%casimir_dir
    !
    ios = f_mkdir_safe(input%outdir)
    IF(ios>0) CALL errore('READ_INPUT', 'cannot create directory: "'//TRIM(input%outdir)//'"',1)
    !
    CALL READ_DATA(input, s, fc2, fc3)
    !
    READ(calculation,*,iostat=ios) input%calculation, input%mode
    IF(ios/=0) THEN
      input%calculation = calculation
      input%mode = "full"
    ENDIF
    WRITE(*,*) "calculation: ", input%calculation, input%mode
    !
    IF(nq<0.and.TRIM(input%calculation)/="grid".and.code=="LW") CALL errore('READ_INPUT', 'Missing nq', 1)    
    !
    IF(TRIM(prefix)==INVALID)THEN
      input%prefix = TRIM(input%calculation)//"."//TRIM(input%mode)
    ELSE
      input%prefix = prefix
    ENDIF
    !
    IF(TRIM(input%calculation) == 'spf' .and. ne < 0) &
      CALL errore('READ_INPUT', 'Missing ne for spf calculation', 1)    
    input%ne = ne
    input%de = de
    input%e0 = e0
    !
    IF(TRIM(input%calculation) == 'final' .and. e_initial < 0) &
      CALL errore('READ_INPUT', 'Missing e_initial for final state calculation', 1)    
    input%e_initial = e_initial
    input%q_initial = q_initial
    ! if we also want the q of the final state:
    input%q_resolved = q_resolved
    input%sigmaq  = sigmaq
    !
    IF(input%casimir_scattering)THEN
      IF(casimir_length_au>0._dp .and. casimir_length_mu>0._dp .and. casimir_length_mm>0._dp) &
        CALL errore('READ_INPUT', "You cannot specify more than one: casimir_length_{au,mu,mm}")
      IF(casimir_length_au<0._dp .and. casimir_length_mu<0._dp .and. casimir_length_mm<0._dp) &
        CALL errore('READ_INPUT', "You must specify one of: casimir_length_{au,mu,mm}")
      IF(casimir_length_au>0._dp) input%casimir_length = casimir_length_au
      IF(casimir_length_mu>0._dp) input%casimir_length = casimir_length_mu/(BOHR_RADIUS_SI*1.d+6)
      IF(casimir_length_mm>0._dp) input%casimir_length = casimir_length_mu/(BOHR_RADIUS_SI*1.d+3)
      WRITE(*,'(5x,a,1f12.0)') "Casimir length (bohr)", input%casimir_length
    ENDIF
    !
    ! Read the configurations:
    !
    ALLOCATE(input%T(nconf), input%sigma(nconf))
    !
    READ(*,'(a1024)', iostat=ios) line
    READ_CARDS : &
    DO WHILE (ios==0)
      !
      READ(line,*,iostat=ios2) word
      IF(ios2/=0) THEN
        READ(*,'(a1024)', iostat=ios) line
        CYCLE READ_CARDS 
      ENDIF
      !
      SELECT CASE (TRIM(word))
        ! ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      CASE ("QPOINTS")
        IF(qpoints_ok) CALL errore("READ_INPUT", "Won't reads q-points twice", 1)
        qpoints_ok = .true.
        !
        IF(code=="TK") THEN
          WRITE(*,*) "Ignoring QPOINTS (code TK)"
          CYCLE READ_CARDS
        ENDIF
        !
        WRITE(*,*) "Reading QPOINTS"
        !
        IF(TRIM(input%calculation) == "grid")THEN
          READ(*,*,iostat=ios) nq1, nq2, nq3
          IF(ios/=0) CALL errore("READ_INPUT", "reading nq1, nq2, nq3 for q-grid calculation", 1)
          line=''
          WRITE(*,"(2x,a,i4,a)") "Read ", qpts%nq, " q-points, "//TRIM(qpts%basis)//" basis"
          !CALL setup_simple_grid(S, nq1,nq2,nq3, qpts) this is done later
          CYCLE READ_CARDS
        ENDIF
        !
        qpts%basis = 'cartesian'
        READ(line,*,iostat=ios) word2, word3
        IF(ios==0) qpts%basis = TRIM(word3(1:9))
        !
        QPOINT_LOOP : & ! ..............................................................
        DO i = 1, nq
          READ(*,'(a1024)', iostat=ios) line
          IF(ios/=0) CALL errore("READ_INPUT","Expecting q point: input error.", 1)
          !
          ! Try to read point and number of points
          READ(line,*, iostat=ios2) xq(1), xq(2), xq(3), naux
          IF(ios2==0) THEN
            IF(i>1) THEN
              xq0 = qpts%xq(:,qpts%nq)
            ELSE
              xq0 = 0._dp
            ENDIF
            IF(SUM((xq-xq0)**2)<1.d-6) CALL errore("READ_INPUT", "q-point repeated, please think for the planet.", 1)
            CALL setup_path(xq0, xq, naux, qpts)
            CYCLE QPOINT_LOOP
          ENDIF
          !
          ! Try to read just the point 
          READ(line,*, iostat=ios2) xq(1), xq(2), xq(3)
          IF(ios2==0) THEN
            CALL setup_path(xq, xq, 1, qpts)
            CYCLE QPOINT_LOOP
          ENDIF
          !
          IF(ios2/=0) CALL errore("READ_INPUT","Expecting q point, got: '"//TRIM(line)//"'.", 1)
          EXIT QPOINT_LOOP
          !
        ENDDO &
        QPOINT_LOOP ! .................................................................
        
        WRITE(*,"(2x,a,i4,a)") "Read ", qpts%nq, " q-points, "//TRIM(qpts%basis)//" basis"
        !
        IF(TRIM(qpts%basis) == "crystal")  THEN
          CALL cryst_to_cart(qpts%nq,qpts%xq,S%bg, +1)
          qpts%basis = "cartesian"
          WRITE(*,"(4x,a)") "q-points converted to cartesian basis"
        ENDIF
        WRITE(*,"(2x,3f12.6)") qpts%xq ! this prints all points, one per line
        WRITE(*,*)
        ! ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      CASE ("CONFIGS")
        IF(configs_ok) CALL errore("READ_INPUT", "Won't reads configs twice", 1)
        configs_ok = .true.
        !
        WRITE(*,*) "Reading CONFIGS", nconf
        DO i = 1,nconf
          READ(*,'(a1024)', iostat=ios2) line
          IF(ios2/=0) CALL errore("READ_INPUT","Expecting configuration: input error.", 1)
          !
          ! try to read sigma and temperature
          READ(line,*,iostat=ios2) input%sigma(i), input%T(i)
          ! If it fails, read just temperature
          IF(ios2/=0) THEN
            READ(line,*,iostat=ios2) input%T(i)
            ! If this fails, complain
            IF(ios2/=0) CALL errore("READ_INPUT","Expecting configuration, got: '"//TRIM(line)//"'.", 1)
            ! reuse previous value of sigma if we read jus ttemperature
            IF(i>1) THEN
              input%sigma(i) = input%sigma(i-1)
            ELSE
              CALL errore("READ_INPUT","I need at least one value of sigma", 1)
            ENDIF
          ENDIF
        ENDDO
        WRITE(*,'(2x,a,/,100(8f9.1,/))') "Temperatures:", input%T
        WRITE(*,'(2x,a,/,100(8f9.1,/))') "Smearings:   ", input%sigma
        WRITE(*,*)
        ! ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      CASE ("ISOTOPES")
        IF(isotopes_ok) CALL errore("READ_INPUT", "Won't reads isotopes twice", 1)
        isotopes_ok = .true.
        !
        WRITE(*,*) "Reading ISOTOPES", S%ntyp
        IF(.not.isotopic_disorder) WRITE(*,*) "WARNING! you did not set isotopic_disorder to true!"
        ALLOCATE(auxs(S%ntyp), auxm(S%ntyp))
        !
        ISOTOPE_TYPE_LOOP : &
        DO i = 1,S%ntyp
          READ(*,'(a1024)', iostat=ios2) line
          IF(ios2/=0) CALL errore("READ_INPUT","Expecting isotope: input error.", 1)
          !
          ! Try to read isotope name and method
          READ(line,*,iostat=ios2) word2, word3
          !
          ! If this fails, complain
          IF(ios2/=0) CALL errore("READ_INPUT","Expecting isotope, got: '"//TRIM(line)//"'.", 1)
          IF(word2 /= S%atm(i)) &
            WRITE(*,"(a,i3,2a)") "WARNING: isotope name from input does not match FC file", i, word2, S%atm(i)
          !
          !
          IF (word3=="natural") THEN
            CALL compute_gs(auxm(i), auxs(i), word2, 0, 0)
            
          ELSE IF (word3=="N") THEN
            READ(line,*,iostat=ios2) word2, word3, atomic_N
            IF(ios2/=0) CALL errore("READ_INPUT","Expecting isotope atomic number: input error.", 2)
            CALL compute_gs(auxm(i), auxs(i), word2, atomic_N, 0)
            
          ELSE IF (word3=="M") THEN
            n_isotopes = 1
            ALLOCATE(isotopes_mass(n_isotopes), isotopes_conc(n_isotopes))
            isotopes_conc = 1._dp
            READ(line,*,iostat=ios2) word2, word3, isotopes_mass(1)
            IF(ios2/=0) CALL errore("READ_INPUT","Expecting isotope atomic mass: input error.", 3)
            CALL compute_gs(auxm(i), auxs(i), word2, atomic_N, n_isotopes, isotopes_mass, isotopes_conc)
            DEALLOCATE(isotopes_mass, isotopes_conc)
            
          ELSE IF (word3=="isotopes") THEN
            READ(line,*,iostat=ios2) word2, word3, n_isotopes
            ALLOCATE(isotopes_mass(n_isotopes), isotopes_conc(n_isotopes))
            DO j = 1,n_isotopes
              READ(*,*, iostat=ios2) isotopes_mass(j), isotopes_conc(j)
              IF(ios2/=0) CALL errore("READ_INPUT","Reading isotope line: input error.", 4)
            ENDDO
            CALL compute_gs(auxm(i), auxs(i), word2, atomic_N, n_isotopes, isotopes_mass, isotopes_conc)
            DEALLOCATE(isotopes_mass, isotopes_conc)

          ELSE
            CALL errore("READ_INPUT","I do not understand this isotope choice '"//TRIM(word2)//"'.", 1)
          ENDIF
        ENDDO &
        ISOTOPE_TYPE_LOOP 
        !
        ! Replace atomic masses with those from input:
        S%amass = auxm * MASS_DALTON_TO_RY
        S%amass_variance = auxs
        DEALLOCATE(auxs, auxm)
        ! ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      CASE DEFAULT
        IF(TRIM(line) /= '') WRITE(*,*) "Skip:", TRIM(line)
      END SELECT
      !
      READ(*,'(a1024)', iostat=ios) line
      word = ''
      !
    ENDDO &
    READ_CARDS
    !
    ! Setup a grid of q-points for which to compute the linewidth
    ! if no "Q_POINTS" section has been found, use the same grid
    ! as we used for integrating the phonon scattering
    ! (i.e. inner and outer grids are the same)
    IF(input%calculation=="grid" .or. code=="TK") THEN
      IF(.not.qpoints_ok .or. code=="TK") THEN
        nq1=nk(1); nq2=nk(2); nq3=nk(3)
        qpoints_ok = .true.
      ENDIF
      CALL setup_simple_grid(S, nq1, nq2, nq3, qpts)
      input%prefix = TRIM(input%prefix)//&
                "."//TRIM(int_to_char(nq1))// &
                "x"//TRIM(int_to_char(nq2))// &
                "x"//TRIM(int_to_char(nq3))
    ENDIF
    !
    ! Set natural isotope concentration for every species, if not read from input
    ! note that, if we're not doing isotope scattering, the values from input are taken.
    IF(input%isotopic_disorder.and..not.isotopes_ok)THEN
      WRITE(*,*) "Setting default isotopes"
      DO j = 1,S%ntyp
        CALL compute_gs(S%amass(j), S%amass_variance(j), S%atm(j), 0, 0)
      ENDDO
      S%amass = S%amass * MASS_DALTON_TO_RY
    ENDIF
    ! Finally, divide the FCs by the sqrt of these masses
    CALL div_mass_fc2(S, fc2)
    CALL fc3%div_mass(S)
    !
    IF(.not.qpoints_ok) CALL errore("READ_INPUT", "I did not find QPOINTS card", 1)
    IF(.not.configs_ok) CALL errore("READ_INPUT", "I did not find CONFIGS card", 1)
    !
  END SUBROUTINE READ_INPUT
  !
  ! <<^V^\\=========================================//-//-//========//O\\//
  ! read everything from files mat2R and mat3R
  SUBROUTINE READ_DATA(input, s, fc2, fc3)
    USE iso_c_binding,  ONLY : c_int
    USE input_fc,       ONLY : same_system, read_fc2, aux_system, &
                               forceconst2_grid, ph_system_info
    USE asr2_module,    ONLY : impose_asr2
    USE io_global,      ONLY : stdout
    USE fc3_interpolate,      ONLY : read_fc3, forceconst3
    IMPLICIT NONE
    !
    TYPE(code_input_type),INTENT(in)        :: input
    TYPE(forceconst2_grid),INTENT(inout) :: fc2
    CLASS(forceconst3),POINTER,INTENT(inout) :: fc3
    TYPE(ph_system_info),INTENT(inout)   :: s
    TYPE(ph_system_info) :: s3
    !
    INTEGER(kind=c_int) :: kb
    !
    CALL read_fc2(input%file_mat2, S,  fc2)
    fc3 => read_fc3(input%file_mat3, S3)
    !
    IF(.not.same_system(S, S3)) THEN
      PRINT*, "WARNING! FC2 and FC3 systems DO NOT MATCH !!!"
    ENDIF
    !
    CALL aux_system(S)
    !
    CALL memstat(kb)
    WRITE(stdout,*) "Reading : done."
    WRITE(stdout,*) "Memory used : ", kb/1000, "Mb"
    !
    IF(input%asr2) CALL impose_asr2(S%nat, fc2)
    ! NOTE: we now divide by the mass in READ_INPUT, as the masses
    !       read from input may be different (i.e. when including isotope scattering)
!    CALL div_mass_fc2(S, fc2)
!     CALL fc3%div_mass(S)
    !
  END SUBROUTINE READ_DATA
  !
END MODULE code_input
! <<^V^\\=========================================//-//-//========//O\\//
