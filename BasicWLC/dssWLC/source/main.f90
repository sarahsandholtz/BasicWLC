PROGRAM MAIN
  USE KEYS, ONLY : ACTION

  IMPLICIT NONE

  CALL READKEY

  SELECT CASE(ACTION)
  CASE('MONTECARLO')
     CALL MCDRIVER
  CASE('BROWNDYN')
     CALL BDDRIVER
  CASE('EQUILDISTRIB')
     CALL EQUILDISTDRIVER
  CASE DEFAULT
     PRINT*, 'UNKNOWN ACTION:', ACTION
     STOP 1
  END SELECT

CONTAINS
  SUBROUTINE EQUILDISTDRIVER
    ! use rejection sampling to generate chain configurations from equilibrium 
    ! distributions
    USE CHAINUTIL, ONLY : CHAIN, SETUPCHAIN, CLEANUPCHAIN, SETCHAINPARAMS,OUTPUTSNAPSHOT
    USE KEYS, ONLY : MAXNPT,OUTFILE,DUMPSNAPSHOTS,SNAPSHOTEVERY,&
         & MCPRINTFREQ,MCTOTSTEPS,SNAPSHOTFILE, EQUILSAMPLETYPE, MCOUTPUTFREQ
    USE SAMPLEUTIL, ONLY : GETEQUILCHAIN

    IMPLICIT NONE

    TYPE(CHAIN), TARGET :: WLCLIST(1)
    TYPE(CHAIN), POINTER :: CHAINP
    INTEGER :: SC, SNAPCT
    DOUBLE PRECISION :: DR(3), PREVCOORDS(6), NEWCOORDS(6)

    CHAINP=>WLCLIST(1); 

    CALL READKEY

    CALL SETUPCHAIN(CHAINP,MAXNPT)
    CALL SETCHAINPARAMS(CHAINP)   
   ! CALL INITIALIZECHAIN(CHAINP,.FALSE.,INITRANGE)

    print*, 'chain info:', chainp%npt
    
    OPEN(UNIT=55,FILE=OUTFILE,STATUS='UNKNOWN')
    DO SC = 1,MCTOTSTEPS             
       IF (SC.GT.1.AND.EQUILSAMPLETYPE.EQ.3) THEN
          PREVCOORDS = NEWCOORDS
          CALL GETEQUILCHAIN(CHAINP,EQUILSAMPLETYPE,NEWCOORDS,PREVCOORDS)
       ELSE
          CALL GETEQUILCHAIN(CHAINP,EQUILSAMPLETYPE,NEWCOORDS)
       ENDIF
       DR = CHAINP%POS(:,CHAINP%NPT)-CHAINP%POS(:,1)
       IF (MOD(SC,MCOUTPUTFREQ).EQ.0) THEN
          PRINT*, 'Chain sample:', SC, DR
       ENDIF
       WRITE(55,*) DR, CHAINP%UVEC(:,1)

        IF (DUMPSNAPSHOTS.AND.MOD(SC,SNAPSHOTEVERY).EQ.0) THEN
          SNAPCT = SNAPCT + 1
          CALL OUTPUTSNAPSHOT(CHAINP,SNAPSHOTFILE,SC,SNAPCT.GT.1)
       ENDIF

    ENDDO
    CLOSE(55)

  END SUBROUTINE EQUILDISTDRIVER

  SUBROUTINE BDDRIVER
    ! run a brownian dynamics simulation
    USE BROWNDYN, ONLY : RUNBROWNDYN
    USE CHAINUTIL, ONLY : CHAIN, SETUPCHAIN, SETCHAINPARAMS, CLEANUPCHAIN, INITIALIZECHAIN, INPUTSNAPSHOT, OUTPUTSNAPSHOT
    USE KEYS, ONLY : NCHAIN, MAXNPT, BDSTEPS, DELTSCL, OUTFILE, &
         & INITRANGE, RESTART, RESTARTFILE, RUNGEKUTTA, DOBROWN, &
         & SKIPREAD, STARTEQUIL, EQUILSAMPLETYPE, EQUILBEADROD,STARTEQUILLP
    USE SAMPLEUTIL, ONLY : GETEQUILCHAIN

    IMPLICIT NONE

    TYPE(CHAIN), ALLOCATABLE, TARGET :: CHAINLIST(:)
    TYPE(CHAIN), POINTER :: CHAINP
    INTEGER :: C, NREAD,b
    DOUBLE PRECISION :: DELT, KT
    DOUBLE PRECISION :: NEWCOORDS(6), PREVCOORDS(6)
    LOGICAL :: SHEARABLESAVE, STRETCHABLESAVE
    DOUBLE PRECISION :: LPSAVE, gsave

    ALLOCATE(CHAINLIST(NCHAIN))
    DO C = 1,NCHAIN
       CHAINP=>CHAINLIST(C)
       CALL SETUPCHAIN(CHAINP,MAXNPT)
       CALL SETCHAINPARAMS(CHAINP)
       CALL INITIALIZECHAIN(CHAINP,.TRUE.,INITRANGE)
      ! PRINT*, 'TESTX1:', SQRT(SUM((CHAINP%POS(:,2)-CHAINP%POS(:,1))**2))       
    ENDDO

    IF (RESTART) THEN
       CALL INPUTSNAPSHOT(CHAINLIST,NCHAIN,RESTARTFILE,SKIPREAD,NREAD)
       IF (NREAD.EQ.NCHAIN) THEN
          PRINT*, 'SUCCESSFULLY READ CHAINS FROM RESTART FILE.', NCHAIN, TRIM(RESTARTFILE)
       ELSE IF (NREAD.EQ.0) THEN
          PRINT*, 'FAILED TO READ ANY CHAINS FROM INPUT FILE'
          STOP 1
       ELSE
          PRINT*, 'FAILED TO READ IN SUFFICIENT CHAINS FROM INPUT FILE. Will cycle through the read configs.', nread, nchain
          DO C = NREAD+1,NCHAIN
             CHAINLIST(C)%POS = CHAINLIST(MOD(C-1,NREAD)+1)%POS
             CHAINLIST(C)%UVEC = CHAINLIST(MOD(C-1,NREAD)+1)%UVEC
          ENDDO
       ENDIF
       CALL OUTPUTSNAPSHOT(CHAINP,'lastread.out',1,.FALSE.)
    ELSE IF (STARTEQUIL) THEN       
       print*, 'Generating equilibrium configurations for all chains'
       DO C = 1,NCHAIN
!          print*, 'Working on chain:', C
          CHAINP=>CHAINLIST(C)
          IF (EQUILBEADROD) THEN
             SHEARABLESAVE = CHAINP%SHEARABLE; STRETCHABLESAVE = CHAINP%STRETCHABLE
             LPSAVE = CHAINP%LP(1); GSAVE = CHAINP%GAM(1)
             CHAINP%SHEARABLE = .FALSE.; CHAINP%STRETCHABLE = .FALSE.
             CHAINP%LP = STARTEQUILLP; CHAINP%GAM = 1D0
          ENDIF

          IF (C.GT.1.AND.EQUILSAMPLETYPE.EQ.3) THEN
             PREVCOORDS = NEWCOORDS
             CALL GETEQUILCHAIN(CHAINP,EQUILSAMPLETYPE,NEWCOORDS,PREVCOORDS)
          ELSE
             CALL GETEQUILCHAIN(CHAINP,EQUILSAMPLETYPE,NEWCOORDS)            
          ENDIF

          IF (EQUILBEADROD) THEN
             CHAINP%SHEARABLE = SHEARABLESAVE; CHAINP%STRETCHABLE = STRETCHABLESAVE
             CHAINP%LP = LPSAVE
             CHAINP%GAM = GSAVE
          ENDIF
       ENDDO
    ENDIF

    CHAINP=>CHAINLIST(1)

    KT = 1D0
    IF (CHAINP%SHEARABLE) THEN
       DELT = DELTSCL*MIN(MINVAL(CHAINP%FRICTR(1:CHAINP%NPT)),MINVAL(CHAINP%FRICTU(1:CHAINP%NPT)))/kT
    ELSE
       DELT = DELTSCL*MINVAL(CHAINP%FRICTR(1:CHAINP%NPT))/kT
    ENDIF

    PRINT*, 'DELT:', DELT
    print*, 'FRICTR:', CHAINP%FRICTR(1:CHAINP%NPT)
    PRINT*, 'FRICTU:', CHAINP%FRICTU(1:CHAINP%NPT)

    CALL RUNBROWNDYN(CHAINLIST,NCHAIN,BDSTEPS,DELT,KT,OUTFILE,RUNGEKUTTA,DOBROWN)

     DO C = 1,NCHAIN
       CHAINP=>CHAINLIST(C)
       CALL CLEANUPCHAIN(CHAINP)
    ENDDO
    DEALLOCATE(CHAINLIST)
  END SUBROUTINE BDDRIVER

  SUBROUTINE MCDRIVER
    USE CHAINUTIL, ONLY : CHAIN, SETUPCHAIN, SETCHAINPARAMS, &
         & CLEANUPCHAIN,INITIALIZECHAIN, GETENERGY
    USE MANYCHAINS, ONLY : CHAINGROUP,SETUPCHAINGROUP,SETCHAINGROUPPARAMS, &
         & INITIALIZESQUARELATTICE, CLEANUPCHAINGROUP,INITIALIZEDIAMONDLATTICE,APPLYDEFORM
    USE KEYS, ONLY : MAXNPT, MCTOTSTEPS, MCSTATSTEPS, MCINITSTEPS, RESTART, &
         & RESTARTFILE,SQUARELATTICE,LS,GAM,NCONNECT,NCHAIN,NFORCE, SETSHEAR, &
         & SHEARGAMMA, NDIAMOND, LENDIAMOND,WIDTHDIAMOND,DIAMONDLATTICE, &
         & INITRANGE, STARTEQUIL,EQUILSAMPLETYPE,PARAMFROMSNAPSHOT
    USE MONTECARLO, ONLY : RUNMONTECARLO, RUNMONTECARLO1CHAIN
    USE INPUTUTIL, ONLY : READSNAPSHOTS
    USE REDISC, ONLY : READPARAMDATA, CLEANUPDATA
    USE SAMPLEUTIL, ONLY : GETEQUILCHAIN
    IMPLICIT NONE
    TYPE(CHAINGROUP), TARGET :: GROUP
    TYPE(CHAINGROUP), POINTER :: CGRP
    TYPE(CHAIN), POINTER :: CHAINP
    DOUBLE PRECISION :: ENERGY
    INTEGER :: B, STARTSTEP,C,NPT,NC,NCON, I
    LOGICAL :: FILEEXISTS,SUCCESS
    DOUBLE PRECISION :: DIST, SHEARMAT(3,3), NEWCOORDS(6)

    CGRP=>GROUP

    NCON = NCONNECT
    IF (SQUARELATTICE) THEN
       NCON = NCON + (NCHAIN/2)**2
    ELSEIF (DIAMONDLATTICE) THEN
       NCON = NCON + NDIAMOND(1)*NDIAMOND(2) + (NDIAMOND(1)+1)*(NDIAMOND(2)+1) - 4
    ENDIF

    CALL SETUPCHAINGROUP(CGRP,NCHAIN,NCON,NFORCE,MAXNPT)
    CALL SETCHAINGROUPPARAMS(CGRP)

    NPT = CGRP%CHAINS(1)%NPT
    NC = NCHAIN/2

    IF (SQUARELATTICE) THEN
       DIST = (NPT-1)/(NC-1)*LS*gam       
       CALL INITIALIZESQUARELATTICE(CGRP,DIST)
    ELSEIF (DIAMONDLATTICE) THEN
       CALL INITIALIZEDIAMONDLATTICE(CGRP,LS*GAM,NDIAMOND,LENDIAMOND,WIDTHDIAMOND)
    ELSE
       DO C = 1,CGRP%NCHAIN
          CHAINP=>CGRP%CHAINS(C)
          CALL INITIALIZECHAIN(CHAINP,.TRUE.,INITRANGE(2))

          IF (STARTEQUIL) THEN
             IF (C.GT.1.AND.EQUILSAMPLETYPE.EQ.3) THEN
               PRINT*, 'Starting equilibration pre-monte carlo using monte carlo of relative coords is not set up yet.'
               STOP 1
             ELSE
                CALL GETEQUILCHAIN(CHAINP,EQUILSAMPLETYPE,NEWCOORDS)
             ENDIF
          ENDIF
       ENDDO
    ENDIF

    ! apply shear deformation
    SHEARMAT = 0D0
    DO I = 1,3
       SHEARMAT(I,I) = 1D0
    ENDDO
    IF (SETSHEAR) THEN
       SHEARMAT(2,3)= SHEARGAMMA
    ENDIF
    CALL APPLYDEFORM(CGRP,SHEARMAT)
    ! CALL SETUPCHAIN(CHAINP,MAXNPT)
    ! CALL SETCHAINPARAMS(CHAINP)
    ! CALL INITIALIZECHAIN(CHAINP,.FALSE.)

    ! CALL READPARAMDATA('shearWLCparams.data')

    STARTSTEP = 0
    IF (RESTART) THEN
       INQUIRE(FILE=RESTARTFILE,EXIST=FILEEXISTS) 
       IF (FILEEXISTS) THEN
          print*, 'Reading structure from file:', TRIM(ADJUSTL(RESTARTFILE))
          IF (PARAMFROMSNAPSHOT) PRINT*, 'Also extracting parameters from this file'
          CALL READSNAPSHOTS(CGRP,RESTARTFILE,PARAMFROMSNAPSHOT,STARTSTEP,SUCCESS)
          print*, 'Successfully read?:', SUCCESS, STARTSTEP
       ELSE
          PRINT*, 'WARNING: no restart file found!'
       ENDIF
    ENDIF

    IF (CGRP%NCHAIN.EQ.1) THEN
       CHAINP=>CGRP%CHAINS(1)
       
       !CHAINP%FORCE = SQRT(DOT_PRODUCT(FORCE(1,:),FORCE(1,:)))
       CALL RUNMONTECARLO1CHAIN(CHAINP,MCTOTSTEPS,MCSTATSTEPS,MCINITSTEPS,STARTSTEP)
      
    ELSE
       CALL RUNMONTECARLO(CGRP,MCTOTSTEPS,MCSTATSTEPS,MCINITSTEPS,STARTSTEP)
    ENDIF

    CALL CLEANUPCHAINGROUP(CGRP)
    !CALL CLEANUPCHAIN(CHAINP)
    !CALL CLEANUPDATA
  END SUBROUTINE MCDRIVER


END PROGRAM MAIN
