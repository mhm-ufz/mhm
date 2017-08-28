!> \file mo_mrm_eval.f90

!> \brief Runs mrm with a specific parameter set and returns required variables, e.g. runoff.

!> \details  Runs mrm with a specific parameter set and returns required variables, e.g. runoff.

!> \authors Stephan Thober
!> \date Sep 2015
module mo_mrm_eval

  implicit none

  public :: mrm_eval

contains

  ! ------------------------------------------------------------------

  !      NAME
  !          mrm_eval

  !>        \brief Runs mrm with a specific parameter set and returns required variables, e.g. runoff.

  !>        \details Runs mrm with a specific parameter set and returns required variables, e.g. runoff.

  !     INTENT(IN)
  !>       \param[in] "real(dp), dimension(:)    :: parameterset"
  !>          a set of global parameter (gamma) to run mHM, DIMENSION [no. of global_Parameters]

  !     INTENT(INOUT)
  !         None

  !     INTENT(OUT)
  !         None

  !     INTENT(IN), OPTIONAL
  !         None

  !     INTENT(INOUT), OPTIONAL
  !         None

  !     INTENT(OUT), OPTIONAL
  !>        \param[out] "real(dp), dimension(:,:), optional  :: runoff"
  !>           returns runoff time series, DIMENSION [nTimeSteps, nGaugesTotal]

  !     RETURN
  !         None

  !     RESTRICTIONS
  !         None

  !     EXAMPLE
  !         None

  !     LITERATURE
  !         None

  !     HISTORY
  !>        \author Stephan Thober
  !>        \date Sep 2015
  !         Modified, Nov 2016, Stephan Thober - implemented second routing process i.e. adaptive timestep
  
  subroutine mrm_eval(parameterset, runoff)

    use mo_kind, only: i4, dp
    use mo_utils, only: ge
    use mo_mrm_global_variables, only: &
         nBasins, &
         read_restart, & ! flag for reading restart
         dirRestartIn, & ! directory containing restart directory
         simPer, & ! simulation period
         nTStepDay, & ! number of timesteps per day
         timestep, & ! simulation timestep in [h]
         perform_mpr, &
         LCYearId, & ! land cover year id
         L1_total_runoff_in, & ! total runoff [mm h-1]
         ! INPUT variables for mRM routing ====================================
         L0_LCover_mRM, & ! L0 land cover
         L0_floodPlain, & ! flood plains at L0 level
         L0_areaCell, &
         L1_areaCell, &
         L1_L11_ID, &
         L11_areaCell, &
         L11_aFloodPlain, & ! flood plains at L11 level
         L11_length, & ! link length
         L11_slope, &
         L11_L1_ID, &
         L11_netPerm, & ! routing order at L11
         L11_fromN, & ! link source at L11
         L11_toN, & ! link target at L11
         L11_nOutlets, &
         basin_mrm, & ! basin_mrm structure
         InflowGauge, &
         resolutionRouting, &
         resolutionHydrology, &
         ! INPUT variables for writing output =================================
         outputFlxState_mrm, & ! output Fluxes
         warmingDays_mrm, & ! warmingDays for each basin
         timeStep_model_outputs_mrm, &
         ! INPUT/OUTPUT variables for mRM routing =============================
         L11_TSrout, & ! routing timestep in seconds
         L11_C1, & ! first muskingum parameter
         L11_C2, & ! second muskigum parameter
         L11_qOUT, & ! routed runoff flowing out of L11 cell
         L11_qTIN, & ! inflow water into the reach at L11
         L11_qTR, & !
         L11_FracFPimp, & ! fraction of impervious layer at L11 scale
         L11_qMod, &
         mRM_runoff ! global variable containing runoff for every gauge
    use mo_common_variables, only: optimize, processMatrix
    use mo_mrm_tools,        only: get_basin_info_mrm
    use mo_mrm_restart,      only: mrm_read_restart_states
    use mo_mrm_routing,      only: mrm_routing
    use mo_mrm_init,         only: variables_default_init_routing, mrm_update_param
    use mo_mrm_write,        only: mrm_write_output_fluxes
    use mo_julian,           only: caldat, julday
    use mo_mrm_constants,    only: HourSecs
!    use mo_mrm_mpr,          only: L11_calc_celerity

    implicit none

    ! input variables
    real(dp), dimension(:), intent(in) :: parameterset
    real(dp), dimension(:,:), allocatable, optional, intent(out) :: runoff       ! dim1=time dim2=gauge

    ! local variables
    integer(i4) :: ii
    integer(i4) :: jj
    integer(i4) :: tt
    integer(i4) :: day
    integer(i4) :: month
    integer(i4) :: year
    integer(i4) :: hour
    integer(i4) :: nTimeSteps
    integer(i4) :: Lcover_yID ! Land cover year ID
    integer(i4) :: s0, e0 ! start and end index at level 0 for current basin
    integer(i4) :: s1, e1 ! start and end index at level 1 for current basin
    integer(i4) :: s11, e11 ! start and end index at L11
    integer(i4) :: s110, e110 ! start and end index of L11 at L0
    integer(i4) :: nrows, ncols
    integer(i4) :: iDischargeTS ! discharge timestep
    real(dp)    :: tsRoutFactor             ! factor between routing and hydrological modelling resolution
    real(dp)    :: tsRoutFactorIn           ! factor between routing and hydrological modelling resolution (temporary variable)
    integer(i4) :: timestep_rout            ! timestep of runoff to rout [h]
    !                                       ! - identical to timestep of input if
    !                                       !   tsRoutFactor is less than 1
    !                                       ! - tsRoutFactor * timestep if
    !                                       !   tsRoutFactor is greater than 1
    !
    real(dp) :: newTime
    logical  :: do_mpr
    real(dp), allocatable :: RunToRout(:) ! Runoff that is input for routing
    real(dp), allocatable :: InflowDischarge(:) ! inflowing discharge
    logical,  allocatable :: mask11(:,:)
    logical  :: do_rout ! flag for performing routing

    if (.not. read_restart) then
       !-------------------------------------------
       ! L11 ROUTING STATE VARIABLES, FLUXES AND
       !             PARAMETERS
       !-------------------------------------------
       call variables_default_init_routing()
    end if

    if (.not. perform_mpr) stop 'MPR cannot be skipped at the moment'

    ! ----------------------------------------
    ! initialize factor between routing resolution and hydrologic model resolution
    ! ----------------------------------------
    tsRoutFactor = 1_i4
    allocate(InflowDischarge(size(InflowGauge%Q, dim=2)))
    InflowDischarge = 0._dp
    ! ----------------------------------------
    ! loop over basins
    ! ----------------------------------------
    do ii = 1, nBasins
       ! read states from restart
       if (read_restart) call mrm_read_restart_states(ii, dirRestartIn(ii))
       !
       ! get basin information at L11 and L110 if routing is activated
       call get_basin_info_mrm(ii,   0, nrows, ncols,   iStart=s0,  iEnd=e0  )
       call get_basin_info_mrm(ii,   1, nrows, ncols,   iStart=s1,  iEnd=e1  )
       call get_basin_info_mrm(ii,  11, nrows, ncols,  iStart=s11,  iEnd=e11, mask=mask11 )
       call get_basin_info_mrm(ii, 110, nrows, ncols, iStart=s110,  iEnd=e110)
       !
       ! initialize routing parameters (has to be called only for Routing option 2 + 3)
       if ((processMatrix(8, 1) .eq. 2) .or. &
           (processMatrix(8, 1) .eq. 3)) then 
         call mrm_update_param(ii, parameterset(processMatrix(8,3) - &
              processMatrix(8,2) + 1:processMatrix(8,3)))
       end if
       ! calculate NtimeSteps for this basin
       nTimeSteps = (simPer(ii)%julEnd - simPer(ii)%julStart + 1) * NTSTEPDAY
       ! initialize timestep
       newTime = real(simPer(ii)%julStart,dp)
       ! initialize land cover year id
       Lcover_yID = 0
       ! initialize variable for runoff for routing
       allocate(RunToRout(e1 - s1 + 1))
       RunToRout = 0._dp
       ! ----------------------------------------
       ! loop over time
       ! ----------------------------------------
       hour = -timestep
       do tt = 1, nTimeSteps
          ! set discharge timestep
          iDischargeTS = ceiling(real(tt,dp) / real(NTSTEPDAY,dp))
          ! calculate current timestep
          call caldat(int(newTime), yy=year, mm=month, dd=day)
          ! -------------------------------------------------------------------
          ! PERFORM ROUTING
          ! -------------------------------------------------------------------
          !
          ! set input variables for routing
          if (processMatrix(8, 1) .eq. 1) then
             ! >>>
             ! >>> original Muskingum routing, executed every time
             ! >>>
             !
             ! determine whether mpr is to be executed
             if( ( LCyearId(year,ii) .NE. Lcover_yId) .or. (tt .EQ. 1) ) then
                do_mpr = perform_mpr
                Lcover_yID = LCyearId(year, ii)
             else
                do_mpr = .false.
             end if
             !
             do_rout = .True.
             L11_tsRout(ii) = (timestep * HourSecs)
             tsRoutFactorIn = 1._dp
             timestep_rout = timestep
             RunToRout = L1_total_runoff_in(s1:e1, tt) ! runoff [mm TST-1] mm per timestep
             InflowDischarge = InflowGauge%Q(iDischargeTS,:) ! inflow discharge in [m3 s-1]
             !
          else if ((processMatrix(8, 1) .eq. 2) .or. &
                   (processMatrix(8, 1) .eq. 3)) then
             ! >>>
             ! >>> adaptive timestep
             ! >>>
             !
             ! set dummy lcover_yID
             Lcover_yID = 1_i4
             !
             do_rout = .False.
             ! calculate factor
             tsRoutFactor = L11_tsRout(ii) / (timestep * HourSecs)
             ! print *, 'routing factor: ', tsRoutFactor
             ! prepare routing call
             if (tsRoutFactor .lt. 1._dp) then
                ! ----------------------------------------------------------------
                ! routing timesteps are shorter than hydrologic time steps
                ! ----------------------------------------------------------------
                ! set all input variables
                tsRoutFactorIn = tsRoutFactor
                RunToRout = L1_total_runoff_in(s1:e1, tt) ! runoff [mm TST-1] mm per timestep
                InflowDischarge = InflowGauge%Q(iDischargeTS,:) ! inflow discharge in [m3 s-1]
                timestep_rout = timestep
                do_rout = .True.
             else
                ! ----------------------------------------------------------------
                ! routing timesteps are longer than hydrologic time steps
                ! ----------------------------------------------------------------
                ! set all input variables
                tsRoutFactorIn = tsRoutFactor
                RunToRout = RunToRout + L1_total_runoff_in(s1:e1, tt)
                InflowDischarge = InflowDischarge + InflowGauge%Q(iDischargeTS, :)
                ! reset tsRoutFactorIn if last period did not cover full period
                if ((tt .eq. nTimeSteps) .and. (mod(tt, nint(tsRoutFactorIn)) .ne. 0_i4)) &
                     tsRoutFactorIn = mod(tt, nint(tsRoutFactorIn))
                if ((mod(tt, nint(tsRoutFactorIn)) .eq. 0_i4) .or. (tt .eq. nTimeSteps)) then
                   InflowDischarge = InflowDischarge / tsRoutFactorIn
                   timestep_rout = nint(real(timestep,dp) * tsRoutFactor)
                   do_rout = .True.
                end if
             end if
          end if

          ! -------------------------------------------------------------------
          ! execute routing
          ! -------------------------------------------------------------------
          if (do_rout) call mRM_routing( &
               ! general INPUT variables
               processMatrix(8, 1), & ! parse process Case to be used
               parameterset, & ! routing par.
               RunToRout, & ! runoff [mm TST-1] mm per timestep old: L1_total_runoff_in(s1:e1, tt), &
               L1_areaCell(s1:e1), &
               L1_L11_Id(s1:e1), &
               L11_areaCell(s11:e11), &
               L11_L1_Id(s11:e11), &
               L11_netPerm(s11:e11), & ! routing order at L11
               L11_fromN(s11:e11), & ! link source at L11
               L11_toN(s11:e11), & ! link target at L11
               L11_nOutlets(ii), & ! number of outlets
               timestep_rout, & ! timestep of runoff to rout [h]
               tsRoutFactorIn, & ! Factor between routing and hydrologic resolution
               basin_mrm%L11_iEnd(ii) - basin_mrm%L11_iStart(ii) + 1, & ! number of Nodes
               basin_mrm%nInflowGauges(ii), &
               basin_mrm%InflowGaugeIndexList(ii,:), &
               basin_mrm%InflowGaugeHeadwater(ii,:), &
               basin_mrm%InflowGaugeNodeList(ii,:), &
               InflowDischarge, &
               basin_mrm%nGauges(ii), &
               basin_mrm%gaugeIndexList(ii,:), &
               basin_mrm%gaugeNodeList(ii,:), &
               ge(resolutionRouting(ii), resolutionHydrology(ii)), &
               ! original routing specific input variables
               L0_LCover_mRM(s0:e0, Lcover_yID), & ! L0 land cover
               L0_floodPlain(s110:e110), & ! flood plains at L0 level
               L0_areaCell(s0:e0), &
               L11_aFloodPlain(s11:e11), & ! flood plains at L11 level
               L11_length(s11:e11 - 1), & ! link length
               L11_slope(s11:e11 - 1), &
               ! general INPUT/OUTPUT variables
               L11_C1(s11:e11), & ! first muskingum parameter
               L11_C2(s11:e11), & ! second muskigum parameter
               L11_qOUT(s11:e11), & ! routed runoff flowing out of L11 cell
               L11_qTIN(s11:e11,:), & ! inflow water into the reach at L11
               L11_qTR(s11:e11,:), & !
               L11_qMod(s11:e11), &
               mRM_runoff(tt, :), &
               ! original routing specific input/output variables
               L11_FracFPimp(s11:e11), & ! fraction of impervious layer at L11 scale
               ! OPTIONAL INPUT variables
               do_mpr)
          ! -------------------------------------------------------------------
          ! reset variables
          ! -------------------------------------------------------------------
          if (processMatrix(8, 1) .eq. 1) then
             ! reset Input variables
             InflowDischarge = 0._dp
             RunToRout = 0._dp
          else if ((processMatrix(8, 1) .eq. 2) .or. &
                   (processMatrix(8, 1) .eq. 3)) then             
             if ((.not. (tsRoutFactorIn .lt. 1._dp)) .and. do_rout) then
                do jj = 1, nint(tsRoutFactorIn)
                   mRM_runoff(tt - jj + 1, :) = mRM_runoff(tt, :)
                end do
                ! reset Input variables
                InflowDischarge = 0._dp
                RunToRout = 0._dp
             end if
          end if
          ! -------------------------------------------------------------------
          ! INCREMENT TIME
          ! -------------------------------------------------------------------
          hour = mod(hour+timestep, 24)
          newTime = julday(day,month,year) + real(hour+timestep,dp)/24._dp
          ! -------------------------------------------------------------------
          ! WRITE OUTPUT
          ! -------------------------------------------------------------------
          if (.not. optimize .and. any(outputFlxState_mrm)) then
             call mrm_write_output_fluxes( &
                  ! basin id
                  ii, &
                  ! output specification
                  timeStep_model_outputs_mrm, &
                  ! time specification
                  warmingDays_mrm(ii), newTime, nTimeSteps, nTStepDay, &
                  tt, day, month, year, timestep, &
                  ! mask specification
                  mask11, &
                  ! output variables
                  L11_qmod(s11:e11))
          end if
       end do
       ! clean runoff variable
       deallocate(RunToRout)
    end do

    ! =========================================================================
    ! SET RUNOFF OUTPUT VARIABLE IF REQUIRED
    ! =========================================================================
    if (present(runoff)) runoff = mRM_runoff

    ! free memory
    deallocate(InflowDischarge)
  end subroutine mrm_eval

end module mo_mrm_eval
