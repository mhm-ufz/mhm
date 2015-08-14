module mo_read_data_routing
  use mo_kind, only: i4, dp
  implicit none
  public :: read_discharge_data
  public :: read_L0_data_routing
  public :: L1_variable_init_routing
  public :: L0_variable_init_routing
  private :: rotate_fdir_variable
contains
  
  subroutine read_L0_data_routing()
    use mo_mrm_constants, only: nodata_i4, nodata_dp ! mRM's global nodata vales
    use mo_append, only: append, paste
    use mo_string_utils, only: num2str
    use mo_message, only: message
    use mo_read_spatial_data, only: read_spatial_data_ascii, read_header_ascii
    use mo_mrm_file, only: &
         file_facc, ufacc, & ! file name and unit of flow acc map
         file_fdir, ufdir, & ! file name and unit of flow dir map
         file_gaugeloc, ugaugeloc, & ! file name and unit of gauge locations m
         file_dem, udem, &
         uLCoverClass
    use mo_global_variables_routing, only: &
         coupling_mode, &
         nBasins, &
         perform_mpr, &
         nLCoverScene, &
         level0, & ! level0 information
         resolutionHydrology, &
         dirMorpho, & ! directories
         dirLCover, &
         LCfilename, &
         L0_mask_mRM, &
         L0_Basin, &
         L0_elev_mRM, & ! level 0 elevation
         L0_elev_read, &
         L0_LCover_mRM, &
         L0_LCover_read, &
         L0_fAcc, & ! flow accumulation on input resolution (L0)
         L0_fDir, & ! flow direction on input resolution (L0)
         L0_gaugeLoc, & ! location of evaluation gauges on input resolution (L0)
         L0_InflowGaugeLoc, & ! location of inflow gauges on input resolution (L0)
         basin_mrm ! basin information for single basins
#ifdef mrm2mhm
    use mo_global_variables, only: &
         basin, & ! to get the global mask
         ! variables that should not be allocated twice if coupled to mhm
         L0_mask, &
         L0_elev, & 
         L0_LCover
#endif    
    implicit none
    ! local variables
    integer(i4) :: iBasin
    integer(i4) :: iVar
    integer(i4) :: iGauge
    character(256) :: fname
    integer(i4) :: nunit
    integer(i4) :: nCells ! number of cells in global_mask
    integer(i4), dimension(:,:), allocatable :: data_i4_2d
    integer(i4), dimension(:,:), allocatable :: dataMatrix_i4
    real(dp), dimension(:,:), allocatable :: data_dp_2d
    logical, dimension(:,:), allocatable :: mask_2d
    logical, dimension(:,:), allocatable :: mask_global

    ! ************************************************
    ! READ SPATIAL DATA FOR EACH BASIN
    ! ************************************************

    ! allocate necessary variables at Level0
    allocate(level0%nrows       (nBasins))
    allocate(level0%ncols       (nBasins))
    allocate(level0%xllcorner   (nBasins))
    allocate(level0%yllcorner   (nBasins))
    allocate(level0%cellsize    (nBasins))
    allocate(level0%nodata_value(nBasins))
    !
    allocate(basin_mrm%L0_iStart    (nBasins))
    allocate(basin_mrm%L0_iEnd      (nBasins))
    allocate(basin_mrm%L0_iStartMask(nBasins))
    allocate(basin_mrm%L0_iEndMask  (nBasins))
    !
    ! allocate necessary variables at Level110
    allocate(basin_mrm%L110_iStart    (nBasins))
    allocate(basin_mrm%L110_iEnd      (nBasins))

    basin_loop: do iBasin = 1, nBasins
       ! Header (to check consistency)
       fName = trim(adjustl(dirMorpho(iBasin))) // trim(adjustl(file_dem))
       call read_header_ascii(trim(fName), udem,   &
            level0%nrows(iBasin),     level0%ncols(iBasin), level0%xllcorner(iBasin), &
            level0%yllcorner(iBasin), level0%cellsize(iBasin), level0%nodata_value(iBasin))

       ! check for L0 and L1 scale consistency
       if( resolutionHydrology(iBasin) .LT. level0%cellsize(iBasin)) then
          call message()
          call message('***ERROR: resolutionHydrology (L1) should be smaller than the input data resolution (L0)')
          call message('          check set-up (in mhm.nml) for basin: ', trim(adjustl(num2str(iBasin))),' ...')
          stop
       end if

       ! DEM + overall mask creation
       fName = trim(adjustl(dirMorpho(iBasin))) // trim(adjustl(file_dem))
       if (coupling_mode .ne. 2) then
          ! only read dem data if not coupled to mhm
          call read_spatial_data_ascii(trim(fName), udem, &
               level0%nrows(iBasin),     level0%ncols(iBasin), level0%xllcorner(iBasin),&
               level0%yllcorner(iBasin), level0%cellsize(iBasin), data_dp_2d, mask_global)
          ! create overall mHM mask on L0 and save indices
          nCells = size(mask_global, dim=1)*size(mask_global, dim=2)
          call append( L0_mask_mRM, reshape(mask_global, (/nCells/)))
       else
#ifdef mrm2mhm
          ! get mask global from mhm variables
          mask_global = reshape(basin%L0_mask(basin%L0_iStartMask(iBasin):basin%L0_iEndMask(iBasin)), &
               (/level0%nrows(iBasin), level0%ncols(iBasin)/))
          nCells = size(mask_global, dim=1)*size(mask_global, dim=2)
#endif
       end if

       ! Saving indices at Level110 irrespective of whether L0_data is shared or not
       if (iBasin .eq. 1) then
          basin_mrm%L110_iStart(iBasin) = 1
          basin_mrm%L110_iEnd  (iBasin) = basin_mrm%L110_iStart(iBasin) + count(mask_global) - 1
       else
          basin_mrm%L110_iStart(iBasin) = basin_mrm%L110_iEnd(iBasin-1) + 1
          basin_mrm%L110_iEnd  (iBasin) = basin_mrm%L110_iStart(iBasin) + count(mask_global) - 1
       end if

       ! check whether L0 data is shared
       if (iBasin .gt. 1) then
          if (L0_Basin(iBasin) .eq. L0_Basin(iBasin - 1)) then
             !
             call message('    Using data of previous basin: ', trim(adjustl(num2str(iBasin))),' ...')
             basin_mrm%L0_iStart(iBasin) = basin_mrm%L0_iStart(iBasin - 1)
             basin_mrm%L0_iEnd  (iBasin) = basin_mrm%L0_iEnd(iBasin - 1)
             !
             basin_mrm%L0_iStartMask(iBasin) = basin_mrm%L0_iStartMask(iBasin - 1 )
             basin_mrm%L0_iEndMask  (iBasin) = basin_mrm%L0_iEndMask(iBasin - 1 )
             !
             ! DO NOT read L0 data
             cycle
             !
          end if
       end if
       !
       call message('    Reading data for basin: ', trim(adjustl(num2str(iBasin))),' ...')
       !
       ! Saving indices of mask and packed data
       if(iBasin .eq. 1) then
          basin_mrm%L0_iStart(iBasin) = 1
          basin_mrm%L0_iEnd  (iBasin) = basin_mrm%L0_iStart(iBasin) + count(mask_global) - 1
          !
          basin_mrm%L0_iStartMask(iBasin) = 1
          basin_mrm%L0_iEndMask  (iBasin) = basin_mrm%L0_iStartMask(iBasin) + nCells - 1
       else
          basin_mrm%L0_iStart(iBasin) = basin_mrm%L0_iEnd(iBasin-1) + 1
          basin_mrm%L0_iEnd  (iBasin) = basin_mrm%L0_iStart(iBasin) + count(mask_global) - 1
          !
          basin_mrm%L0_iStartMask(iBasin) = basin_mrm%L0_iEndMask(iBasin-1) + 1
          basin_mrm%L0_iEndMask  (iBasin) = basin_mrm%L0_iStartMask(iBasin) + nCells - 1
       end if
       ! Read L0 data, if restart is false
       read_L0_data: if ( perform_mpr ) then
          !
          if (coupling_mode .ne. 2) then
             ! put global nodata value into array (probably not all grid cells have values)
             data_dp_2d = merge(data_dp_2d,  nodata_dp, mask_global)
             ! put data in variable
             call append( L0_elev_read, pack(data_dp_2d, mask_global) )
             ! deallocate arrays
             deallocate(data_dp_2d)
          end if

          ! read fAcc, fDir, gaugeLoc
          do iVar = 1, 3
             select case (iVar)
             case(1) ! flow accumulation
                fName = trim(adjustl(dirMorpho(iBasin)))//trim(adjustl(file_facc))
                nunit = ufacc
             case(2) ! flow direction
                fName = trim(adjustl(dirMorpho(iBasin)))//trim(adjustl(file_fdir))
                nunit = ufdir
             case(3) ! location of gauging stations
                fName = trim(adjustl(dirMorpho(iBasin)))//trim(adjustl(file_gaugeloc))
                nunit = ugaugeloc
             end select
             !
             ! reading and transposing
             call read_spatial_data_ascii(trim(fName), nunit,                               &
                  level0%nrows(iBasin),     level0%ncols(iBasin), level0%xllcorner(iBasin), &
                  level0%yllcorner(iBasin), level0%cellsize(iBasin), data_i4_2d, mask_2d)
             ! put global nodata value into array (probably not all grid cells have values)
             data_i4_2d = merge(data_i4_2d,  nodata_i4, mask_2d)
             ! put data into global L0 variable
             select case (iVar)
             case(1) ! flow accumulation
                call append( L0_fAcc,    pack(data_i4_2d, mask_global) )
             case(2) ! flow direction
                ! rotate flow direction and any other variable with directions
                ! NOTE: ONLY when ASCII files are read
                call rotate_fdir_variable(data_i4_2d)
                ! append
                call append( L0_fDir,    pack(data_i4_2d, mask_global) )
             case(3) ! location of evaluation and inflow gauging stations
                ! evaluation gauges
                ! Input data check
                do iGauge = 1, basin_mrm%nGauges(iBasin)
                   ! If gaugeId is found in gauging location file?
                   if (.not. any(data_i4_2d .EQ. basin_mrm%gaugeIdList(iBasin, iGauge))) then
                      call message()
                      call message('***ERROR: Gauge ID "', trim(adjustl(num2str(basin_mrm%gaugeIdList(iBasin, iGauge)))), &
                           '" not found in ' )
                      call message('          Gauge location input file: ', &
                           trim(adjustl(dirMorpho(iBasin)))//trim(adjustl(file_gaugeloc)))
                      stop
                   end if
                end do

                call append( L0_gaugeLoc, pack(data_i4_2d, mask_global) )

                ! inflow gauges
                ! if no inflow gauge for this subbasin exists still matirx with dim of subbasin has to be paded
                if (basin_mrm%nInflowGauges(iBasin) .GT. 0_i4) then
                   ! Input data check
                   do iGauge = 1, basin_mrm%nInflowGauges(iBasin)
                      ! If InflowGaugeId is found in gauging location file?
                      if (.not. any(data_i4_2d .EQ. basin_mrm%InflowGaugeIdList(iBasin, iGauge))) then
                         call message()
                         call message('***ERROR: Inflow Gauge ID "', &
                              trim(adjustl(num2str(basin_mrm%InflowGaugeIdList(iBasin, iGauge)))), &
                              '" not found in ' )
                         call message('          Gauge location input file: ', &
                              trim(adjustl(dirMorpho(iBasin)))//trim(adjustl(file_gaugeloc)))
                         stop
                      end if
                   end do
                end if

                call append( L0_InflowGaugeLoc, pack(data_i4_2d, mask_global) )

             end select
             !
             ! deallocate arrays
             deallocate(data_i4_2d, mask_2d)
             !
          end do
       end if read_L0_data
       !
       if (coupling_mode .ne. 2) then
          ! LCover read in is realized seperated because of unknown number of scenes
          do iVar = 1, nLCoverScene
             fName = trim(adjustl(dirLCover(iBasin)))//trim(adjustl(LCfilename(iVar)))
             call read_spatial_data_ascii(trim(fName), ulcoverclass,                        &
                  level0%nrows(iBasin),     level0%ncols(iBasin), level0%xllcorner(iBasin), &
                  level0%yllcorner(iBasin), level0%cellsize(iBasin), data_i4_2d, mask_2d)
             
             ! put global nodata value into array (probably not all grid cells have values)
             data_i4_2d = merge(data_i4_2d,  nodata_i4, mask_2d)
             call paste(dataMatrix_i4, pack(data_i4_2d, mask_global), nodata_i4)
             !
             deallocate(data_i4_2d)
          end do
          !
          call append( L0_LCover_read, dataMatrix_i4 )
          ! free memory
          deallocate(dataMatrix_i4)
       end if

       ! free memory
       deallocate(mask_global)
       
    end do basin_loop

    ! ----------------------------------------------------------------
    ! assign pointers for L0 variables
    ! ----------------------------------------------------------------
    if (coupling_mode .ne. 2) then
       L0_elev_mRM => L0_elev_read
       L0_LCover_mRM => L0_LCover_read
       basin_mRM%L0_mask => L0_mask_mRM
    else
#ifdef mrm2mhm
       L0_elev_mRM => L0_elev
       L0_LCover_mRM => L0_LCover
       basin_mrm%L0_mask => L0_mask
#endif
    end if
       

  end subroutine read_L0_data_routing

  ! ************************************************
  ! INITIALIZE LEVEL0 INFORMATION
  ! ************************************************

  ! ------------------------------------------------------------------

  !      NAME
  !          L0_variable_init_routing

  !>        \brief   level 0 variable initialization

  !>        \details following tasks are performed for L0 data sets
  !>                 -  cell id & numbering
  !>                 -  storage of cell cordinates (row and coloum id)
  !>                 If a variable is added or removed here, then it also has to
  !>                 be added or removed in the subroutine config_variables_set in
  !>                 module mo_restart and in the subroutine set_config in module
  !>                 mo_set_netcdf_restart

  !     INTENT(IN)
  !>        \param[in] "integer(i4)               :: iBasin"  basin id

  !     INTENT(INOUT)
  !>        \param[in,out] "integer(i4), dimension(:) :: soilId_isPresent"
  !>        flag to indicate wether a given soil-id is present or not, DIMENSION [nSoilTypes]

  !     INTENT(OUT)
  !         None

  !     INTENT(IN), OPTIONAL
  !         None

  !     INTENT(INOUT), OPTIONAL
  !         None

  !     INTENT(OUT), OPTIONAL
  !         None

  !     RETURN
  !         None

  !     RESTRICTIONS
  !         None

  !     EXAMPLE
  !         None

  !     LITERATURE
  !         None

  !     HISTORY
  !         \author  Rohini Kumar
  !         \date    Jan 2013
  !         Modified
  !         Rohini Kumar & Matthias Cuntz, May 2014 - cell area calulation based on a regular lat-lon grid or
  !                                                   on a regular X-Y coordinate system
  !         Matthias Cuntz,                May 2014 - changed empirical distribution function
  !                                                   so that doubles get the same value
  !         Stephan Thober,                Aug 2015 - adapted for mRM

  subroutine L0_variable_init_routing(iBasin)
    use mo_append,        only: append
    use mo_constants,     only: TWOPI_dp, RadiusEarth_dp
    use mo_mrm_constants, only: nodata_i4, nodata_dp
    use mo_tools, only: get_basin_info_mrm
    use mo_global_variables_routing, only: &
         L0_areaCell,            &
         level0,                 &
         L0_cellCoor, &
         L0_Id, &
         iFlag_cordinate_sys
    implicit none

    integer(i4), intent(in) :: iBasin

    ! local variables
    integer(i4)                               :: nCells
    integer(i4), dimension(:,:), allocatable  :: cellCoor
    integer(i4), dimension(:), allocatable    :: Id
    real(dp), dimension(:), allocatable       :: areaCell
    real(dp), dimension(:,:), allocatable     :: areaCell_2D

    integer(i4)                               :: nrows, ncols
    integer(i4)                               :: iStart, iEnd
    logical, dimension(:,:), allocatable      :: mask

    integer(i4)                               :: i, j, k
    real(dp)                                  :: rdum, degree_to_radian, degree_to_metre

    !--------------------------------------------------------
    ! STEPS::
    ! 1) Estimate each variable locally for a given basin
    ! 2) Pad each variable to its corresponding global one
    !--------------------------------------------------------

    ! level-0 information
    call get_basin_info_mrm( iBasin, 0, nrows, ncols, nCells=nCells, iStart=iStart, iEnd=iEnd, mask=mask )

    allocate( cellCoor(nCells,2) )
    allocate(       Id(nCells  ) )
    allocate( areaCell(nCells  ) )
    allocate( areaCell_2D(nrows,ncols) )

    cellCoor(:,:) =  nodata_i4
    Id(:)         =  nodata_i4
    areaCell(:)   =  nodata_dp
    areaCell_2D(:,:) =  nodata_dp

    !------------------------------------------------
    ! start looping for cell cordinates and ids
    !------------------------------------------------
    k = 0
    do j = 1, ncols
       do i = 1, nrows
          if ( .NOT. mask(i,j) ) cycle
          k = k + 1
          Id(k)         = k
          cellCoor(k,1) = i
          cellCoor(k,2) = j
       end do
    end do

    ! ESTIMATE AREA [m2]

    ! regular X-Y coordinate system
    if(iFlag_cordinate_sys .eq. 0) then
       areaCell(:) = level0%cellsize(iBasin) * level0%cellsize(iBasin)

    ! regular lat-lon coordinate system
    else if(iFlag_cordinate_sys .eq. 1) then

       degree_to_radian = TWOPI_dp / 360.0_dp
       degree_to_metre  = RadiusEarth_dp*TWOPI_dp/360.0_dp
       do i = ncols, 1, -1
         j =  ncols - i + 1
         ! get latitude in degrees
         rdum = level0%yllcorner(iBasin) + (real(j,dp)-0.5_dp) * level0%cellsize(iBasin)
         ! convert to radians
         rdum = rdum*degree_to_radian
         !    AREA [m2]
         areaCell_2D(:,i) = (level0%cellsize(iBasin) * cos(rdum) * degree_to_metre) * (level0%cellsize(iBasin)*degree_to_metre)
       end do
       areaCell(:) = pack( areaCell_2D(:,:), mask)

    end if

    !--------------------------------------------------------
    ! Start padding up local variables to global variables
    !--------------------------------------------------------
    call append( L0_cellCoor, cellCoor )
    call append( L0_Id, Id             )
    call append( L0_areaCell, areaCell )

    ! free space
    deallocate(cellCoor, Id, areaCell, areaCell_2D, mask)

  end subroutine L0_variable_init_routing

  ! ************************************************
  ! INITIALIZE LEVEL1 INFORMATION
  ! ************************************************
  subroutine L1_variable_init_routing(iBasin)
    use mo_mrm_constants, only: nodata_dp
    use mo_append, only: append ! append vector
    use mo_tools, only: get_basin_info_mrm, calculate_grid_properties
    use mo_global_variables_routing, only: &
         level0, &
         resolutionHydrology, &
         L0_areaCell, &
         L1_areaCell, &
         level1, &
         nBasins, &
         basin_mrm
    
    implicit none
    ! input variables
    integer(i4), intent(in) :: iBasin
    ! local variables
    integer(i4)                               :: nrows0, ncols0
    integer(i4)                               :: iStart0, iEnd0
    real(dp)                                  :: xllcorner0, yllcorner0
    real(dp)                                  :: cellsize0
    logical, dimension(:,:), allocatable      :: mask0
    real(dp), dimension(:,:), allocatable     :: areaCell0_2D

    integer(i4)                               :: nrows1, ncols1
    logical, dimension(:,:), allocatable      :: mask1

    integer(i4)                               :: nCells
    real(dp), dimension(:), allocatable       :: areaCell

    real(dp)                                  :: cellFactorHydro

    integer(i4)                               :: iup, idown
    integer(i4)                               :: jl, jr

    integer(i4)                               :: i, j, k, ic, jc

    !--------------------------------------------------------
    ! STEPS::
    ! 1) Estimate each variable locally for a given basin
    ! 2) Pad each variable to its corresponding global one
    !--------------------------------------------------------

    ! level-0 information
    call get_basin_info_mrm( iBasin, 0, nrows0, ncols0, iStart=iStart0, iEnd=iEnd0, mask=mask0, &
         xllcorner=xllcorner0, yllcorner=yllcorner0, cellsize=cellsize0     )

    if(iBasin == 1) then
       allocate( level1%nrows        (nBasins) )
       allocate( level1%ncols        (nBasins) )
       allocate( level1%xllcorner    (nBasins) )
       allocate( level1%yllcorner    (nBasins) )
       allocate( level1%cellsize     (nBasins) )
       allocate( level1%nodata_value (nBasins) )
    end if

    ! grid properties
    call calculate_grid_properties( nrows0, ncols0, xllcorner0, yllcorner0, cellsize0, nodata_dp,         &
         resolutionHydrology(iBasin) , &
         level1%nrows(iBasin), level1%ncols(iBasin), level1%xllcorner(iBasin), &
         level1%yllcorner(iBasin), level1%cellsize(iBasin), level1%nodata_value(iBasin) )

    ! level-1 information
    call get_basin_info_mrm( iBasin, 1, nrows1, ncols1 )

    ! cellfactor = leve1-1 / level-0
    cellFactorHydro = level1%cellsize(iBasin) / level0%cellsize(iBasin)

    ! allocation and initalization of mask at level-1
    allocate( mask1(nrows1, ncols1) )
    mask1(:,:) = .FALSE.

    ! create mask at level-1
    do j=1,ncols0
       jc = ceiling( real(j,dp)/cellFactorHydro )
       do i=1,nrows0
          if ( .NOT. mask0(i,j) ) cycle
          ic = ceiling( real(i,dp)/cellFactorHydro )
          mask1(ic,jc) = .TRUE.
       end do
    end do

    ! level-0 cell area
    allocate( areaCell0_2D(nrows0,ncols0) )
    areaCell0_2D(:,:) = UNPACK( L0_areaCell(iStart0:iEnd0), mask0, nodata_dp )

    ! estimate ncells and initalize related variables
    nCells = count( mask1 )

    ! allocate and initalize cell1 related variables
    allocate( areaCell  (nCells   ) )

    k   = 0
    do jc=1,ncols1
       do ic=1,nrows1
          if ( .NOT. mask1(ic,jc) ) cycle
          k = k + 1

          ! coord. of all corners -> of finer scale level-0
          iup   = (ic-1) * nint(cellFactorHydro,i4) + 1
          idown =    ic  * nint(cellFactorHydro,i4)
          jl    = (jc-1) * nint(cellFactorHydro,i4) + 1
          jr    =    jc  * nint(cellFactorHydro,i4)

          ! constrain the range of up, down, left, and right boundaries
          if(iup   < 1      ) iup =  1
          if(idown > nrows0 ) idown =  nrows0
          if(jl    < 1      ) jl =  1
          if(jr    > ncols0 ) jr =  ncols0

          ! effective area [km2] & total no. of L0 cells within a given L1 cell
          areaCell(k) =   sum( areacell0_2D(iup:idown, jl:jr), mask0(iup:idown, jl:jr) )*1.0E-6

       end do
    end do


    !--------------------------------------------------------
    ! Start padding up local variables to global variables
    !--------------------------------------------------------
    if( iBasin .eq. 1 ) then

       allocate(basin_mrm%L1_iStart(nBasins))
       allocate(basin_mrm%L1_iEnd  (nBasins))
       allocate(basin_mrm%L1_iStartMask(nBasins))
       allocate(basin_mrm%L1_iEndMask   (nBasins))

       ! basin information
       basin_mrm%L1_iStart(iBasin) = 1
       basin_mrm%L1_iEnd  (iBasin) = basin_mrm%L1_iStart(iBasin) + nCells - 1

       basin_mrm%L1_iStartMask(iBasin) = 1
       basin_mrm%L1_iEndMask  (iBasin) = basin_mrm%L1_iStartMask(iBasin) + nrows1*ncols1 - 1

    else

       ! basin information
       basin_mrm%L1_iStart(iBasin) = basin_mrm%L1_iEnd(iBasin-1) + 1
       basin_mrm%L1_iEnd  (iBasin) = basin_mrm%L1_iStart(iBasin) + nCells - 1

       basin_mrm%L1_iStartMask(iBasin) = basin_mrm%L1_iEndMask(iBasin-1) + 1
       basin_mrm%L1_iEndMask  (iBasin) = basin_mrm%L1_iStartMask(iBasin) + nrows1*ncols1 - 1

    end if

    call append( basin_mrm%L1_Mask,  RESHAPE( mask1, (/nrows1*ncols1/)  )  )
    call append( L1_areaCell, areaCell )

    ! free space
    deallocate( mask0, areaCell0_2D, mask1, areaCell )

  end subroutine L1_variable_init_routing
  ! ************************************************
  ! READ DISCHARGE TIME SERIES
  ! ************************************************
  subroutine read_discharge_data()
    use mo_message, only: message
    use mo_append, only: paste
    use mo_string_utils, only: num2str
    use mo_read_timeseries, only: read_timeseries
    use mo_file, only: udischarge
    use mo_mrm_constants, only: nodata_dp
    use mo_global_variables_routing, only: &
         nBasins, &
         mRM_runoff, & ! variable storing runoff for each gauge
         nGaugesTotal, gauge, nMeasPerDay, & ! evaluaton gauging station information
         nInflowGaugesTotal, InflowGauge, & ! inflow stations information
         evalPer, & ! model evaluation period (for discharge read in)
         optimize, & ! optimizeation flag for some error checks
         opti_function, & ! opti_function that determines to what data to calibrate
         nTstepDay, &
         simPer ! model simulation period (for inflow read in)
    !
    implicit none
    ! input variables
    !
    ! local variables
    integer(i4) :: iGauge
    integer(i4) :: iBasin
    integer(i4) :: maxTimeSteps
    character(256) :: fName ! file name of file to read
    integer(i4), dimension(3) :: start_tmp, end_tmp
    real(dp), dimension(:), allocatable :: data_dp_1d
    logical, dimension(:), allocatable :: mask_1d

    !----------------------------------------------------------
    ! INITIALIZE RUNOFF
    !----------------------------------------------------------
    maxTimeSteps = maxval( simPer(1:nBasins)%julEnd - simPer(1:nBasins)%julStart + 1 ) * nTstepDay
    allocate( mRM_runoff(maxTimeSteps, nGaugesTotal) )
    mRM_runoff = nodata_dp

    ! READ GAUGE DATA
    do iGauge = 1, nGaugesTotal
       ! get basin id
       iBasin = gauge%basinId(iGauge)
       ! get start and end dates
       start_tmp = (/evalPer(iBasin)%yStart, evalPer(iBasin)%mStart, evalPer(iBasin)%dStart/)
       end_tmp   = (/evalPer(iBasin)%yEnd,   evalPer(iBasin)%mEnd,   evalPer(iBasin)%dEnd  /)
       ! evaluation gauge
       fName = trim(adjustl(gauge%fname(iGauge)))
       call read_timeseries(trim(fName), udischarge, &
            start_tmp, end_tmp, optimize, opti_function, &
            data_dp_1d, mask=mask_1d, nMeasPerDay=nMeasPerDay)
       data_dp_1d = merge(data_dp_1d, nodata_dp, mask_1d)
       call paste(gauge%Q, data_dp_1d, nodata_dp )
       deallocate (data_dp_1d)
    end do
    !
    ! inflow gauge
    !
    ! in mhm call InflowGauge%Q has to be initialized -- dummy allocation with period of basin 1 and initialization
    if (nInflowGaugesTotal .EQ. 0) then
       allocate( data_dp_1d( maxval( simPer(:)%julEnd  - simPer(:)%julStart + 1 ) ) )
       data_dp_1d = nodata_dp
       call paste(InflowGauge%Q, data_dp_1d, nodata_dp)
    else

       do iGauge = 1, nInflowGaugesTotal
          ! get basin id
          iBasin = InflowGauge%basinId(iGauge)
          ! get start and end dates
          start_tmp = (/simPer(iBasin)%yStart, simPer(iBasin)%mStart, simPer(iBasin)%dStart/)
          end_tmp   = (/simPer(iBasin)%yEnd,   simPer(iBasin)%mEnd,   simPer(iBasin)%dEnd  /)
          ! inflow gauge
          fName = trim(adjustl(InflowGauge%fname(iGauge)))
          call read_timeseries(trim(fName), udischarge, &
               start_tmp, end_tmp, optimize, opti_function, &
               data_dp_1d, mask=mask_1d, nMeasPerDay=nMeasPerDay)
          if ( .NOT. (all(mask_1d)) ) then
             call message()
             call message('***ERROR: Nodata values in inflow gauge time series. File: ', trim(fName))
             call message('          During simulation period from ', num2str(simPer(iBasin)%yStart) &
                  ,' to ', num2str(simPer(iBasin)%yEnd))
             stop
          end if
          data_dp_1d = merge(data_dp_1d, nodata_dp, mask_1d)
          call paste(InflowGauge%Q, data_dp_1d, nodata_dp)
          deallocate (data_dp_1d)
       end do
    end if

  end subroutine read_discharge_data
  ! ------------------------------------------------------------------
  ! Rotate fdir variable to the new coordinate system
  ! L. Samaniego & R. Kumar
  ! ------------------------------------------------------------------
  subroutine rotate_fdir_variable( x )
    USE mo_mrm_constants,      ONLY: nodata_i4    ! mHM's global nodata vales

    implicit none

    integer(i4), dimension(:,:), intent(INOUT) :: x
    ! local
    integer(i4)                                :: i, j

    !-------------------------------------------------------------------
    ! NOTE:
    !
    !     Since the DEM was transposed from (lat,lon) to (lon,lat), i.e.
    !     new DEM = transpose(DEM_old), then
    !
    !     the flow direction X (which was read) for every i, j cell needs
    !     to be rotated as follows
    !
    !                 X(i,j) = [R] * {uVector}
    !
    !     with
    !     {uVector} denoting the fDir_old (read) in vector form, and
    !               e.g. dir 8 => {-1, -1, 0 }
    !     [R]       denting a full rotation matrix to transform the flow
    !               direction into the new coordinate system (lon,lat).
    !
    !     [R] = [rx][rz]
    !
    !     with
    !           |      1       0      0 |
    !     [rx] =|      0   cos T  sin T | = elemental rotation along x axis
    !           |      0  -sin T  cos T |
    !
    !           |  cos F   sin F      0 |
    !     [rz] =| -sin F   cos F      0 | = elemental rotation along z axis
    !           |      0       0      1 |
    !
    !     and T = pi, F = - pi/2
    !     thus
    !          !  0  -1   0 |
    !     [R] =| -1   0   0 |
    !          |  0   0  -1 |
    !     making all 8 directions the following transformation were
    !     obtained.
    !-------------------------------------------------------------------

    do i = 1, size(x,1)
       do j = 1, size(x,2)
          if ( x(i,j)  .eq. nodata_i4 ) cycle
          select case ( x(i,j) )
          case(1)
             x(i,j) =   4
          case(2)
             x(i,j) =   2
          case(4)
             x(i,j) =   1
          case(8)
             x(i,j) = 128
          case(16)
             x(i,j) =  64
          case(32)
             x(i,j) =  32
          case(64)
             x(i,j) =  16
          case(128)
             x(i,j) =   8
          end select
       end do
    end do

end subroutine rotate_fdir_variable

end module mo_read_data_routing
