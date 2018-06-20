!>       \file mo_common_restart.f90

!>       \brief TODO: add description

!>       \details TODO: add description

!>       \authors Robert Schweppe

!>       \date Jun 2018

! Modifications:

module mo_common_restart

  IMPLICIT NONE

  PRIVATE

  PUBLIC :: write_grid_info
  PUBLIC :: read_grid_info     ! read restart files for configuration from a given path


  ! ------------------------------------------------------------------

CONTAINS


  !    NAME
  !        write_grid_info

  !    PURPOSE
  !>       \brief write restart files for each basin

  !>       \details write restart files for each basin. For each basin
  !>       three restart files are written. These are xxx_states.nc,
  !>       xxx_L11_config.nc, and xxx_config.nc (xxx being the three digit
  !>       basin index). If a variable is added here, it should also be added
  !>       in the read restart routines below.

  !    INTENT(IN)
  !>       \param[in] "type(Grid) :: grid_in"      level to be written
  !>       \param[in] "character(*) :: level_name" level_id

  !    INTENT(INOUT)
  !>       \param[inout] "type(NcDataset) :: nc" NcDataset to write information to

  !    HISTORY
  !>       \authors Stephan Thober

  !>       \date Jun 2014

  ! Modifications:
  ! Stephan Thober     Aug  2015 - moved write of routing states to mRM
  ! David Schaefer     Nov  2015 - mo_netcdf
  ! Stephan Thober     Nov  2016 - moved processMatrix to common variables
  ! Zink M. Demirel C. Mar 2017 - Added Jarvis soil water stress function at SM process(3)
  ! Robert Schweppe    Feb 2018 - Removed all L0 references
  ! Robert Schweppe    Jun 2018 - refactoring and reformatting


  subroutine write_grid_info(grid_in, level_name, nc)

    use mo_common_constants, only : nodata_dp, nodata_i4
    use mo_common_variables, only : Grid
    use mo_kind, only : dp, i4
    use mo_netcdf, only : NcDataset, NcDimension, NcVariable

    implicit none

    ! level to be written
    type(Grid), intent(in) :: grid_in

    ! level_id
    character(*), intent(in) :: level_name

    ! NcDataset to write information to
    type(NcDataset), intent(inout) :: nc

    type(NcDimension) :: rows, cols

    type(NcVariable) :: var


    rows = nc%setDimension("nrows" // trim(level_name), grid_in%nrows)
    cols = nc%setDimension("ncols" // trim(level_name), grid_in%ncols)

    ! now set everything related to the grid
    var = nc%setVariable("L" // trim(level_name) // "_basin_mask", "i32", (/rows, cols/))
    call var%setFillValue(nodata_i4)
    ! transform from logical to i32
    call var%setData(merge(1_i4, 0_i4, grid_in%mask))
    call var%setAttribute("long_name", "Mask at level " // trim(level_name))

    var = nc%setVariable("L" // trim(level_name) // "_basin_lat", "f64", (/rows, cols/))
    call var%setFillValue(nodata_dp)
    call var%setData(grid_in%y)
    call var%setAttribute("long_name", "Latitude at level " // trim(level_name))

    var = nc%setVariable("L" // trim(level_name) // "_basin_lon", "f64", (/rows, cols/))
    call var%setFillValue(nodata_dp)
    call var%setData(grid_in%x)
    call var%setAttribute("long_name", "Longitude at level " // trim(level_name))

    var = nc%setVariable("L" // trim(level_name) // "_basin_cellarea", "f64", (/rows, cols/))
    call var%setFillValue(nodata_dp)
    call var%setData(unpack(grid_in%CellArea * 1.0E-6_dp, grid_in%mask, nodata_dp))
    call var%setAttribute("long_name", "Cell area at level " // trim(level_name))

    call nc%setAttribute("xllcorner_L" // trim(level_name), grid_in%xllcorner)
    call nc%setAttribute("yllcorner_L" // trim(level_name), grid_in%yllcorner)
    call nc%setAttribute("cellsize_L" // trim(level_name), grid_in%cellsize)
    call nc%setAttribute("nrows_L" // trim(level_name), grid_in%nrows)
    call nc%setAttribute("ncols_L" // trim(level_name), grid_in%ncols)
    call nc%setAttribute("nCells_L" // trim(level_name), grid_in%nCells)

  end subroutine write_grid_info


  ! ------------------------------------------------------------------

  !    NAME
  !        read_grid_info

  !    PURPOSE
  !>       \brief reads configuration apart from Level 11 configuration
  !>       from a restart directory

  !>       \details read configuration variables from a given restart
  !>       directory and initializes all configuration variables,
  !>       that are initialized in the subroutine initialise,
  !>       contained in module mo_startup.

  !    INTENT(IN)
  !>       \param[in] "integer(i4) :: iBasin"      number of basin
  !>       \param[in] "character(256) :: InPath"   Input Path including trailing slash
  !>       \param[in] "character(*) :: level_name" level_name (id)
  !>       \param[in] "character(*) :: fname_part" filename part (either "mHM" or "mRM")

  !    INTENT(INOUT)
  !>       \param[inout] "type(Grid) :: new_grid" grid to save information to

  !    HISTORY
  !>       \authors Stephan Thober

  !>       \date Apr 2013

  ! Modifications:
  ! David Schaefer     Nov 2015 - mo_netcdf
  ! Zink M. Demirel C. Mar 2017 - Added Jarvis soil water stress function at SM process(3)
  ! Robert Schweppe    Feb 2018 - Removed all L0 references
  ! Robert Schweppe    Jun 2018 - refactoring and reformatting

  subroutine read_grid_info(iBasin, InPath, level_name, fname_part, new_grid)

    use mo_common_variables, only : Grid
    use mo_kind, only : dp, i4
    use mo_message, only : message
    use mo_netcdf, only : NcDataset, NcVariable
    use mo_string_utils, only : num2str

    implicit none

    ! number of basin
    integer(i4), intent(in) :: iBasin

    ! Input Path including trailing slash
    character(256), intent(in) :: InPath

    ! level_name (id)
    character(*), intent(in) :: level_name

    ! filename part (either "mHM" or "mRM")
    character(*), intent(in) :: fname_part

    ! grid to save information to
    type(Grid), intent(inout) :: new_grid

    ! dummy, 2 dimension I4
    integer(i4), dimension(:, :), allocatable :: dummyI2

    ! dummy, 2 dimension DP
    real(dp), dimension(:, :), allocatable :: dummyD2

    character(256) :: Fname

    type(NcDataset) :: nc

    type(NcVariable) :: var

    integer(i4) :: k


    ! read config
    fname = trim(InPath) // trim(fname_part) // '_restart_' // trim(num2str(iBasin, '(i3.3)')) // '.nc' ! '_restart.nc'
    call message('    Reading config from     ', trim(adjustl(Fname)), ' ...')

    nc = NcDataset(fname, "r")

    ! <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    ! Read L1 variables <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    ! <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    ! read the grid properties
    call nc%getAttribute("xllcorner_L" // trim(level_name), new_grid%xllcorner)
    call nc%getAttribute("yllcorner_L" // trim(level_name), new_grid%yllcorner)
    call nc%getAttribute("nrows_L" // trim(level_name), new_grid%nrows)
    call nc%getAttribute("ncols_L" // trim(level_name), new_grid%ncols)
    call nc%getAttribute("cellsize_L" // trim(level_name), new_grid%cellsize)
    call nc%getAttribute("nCells_L" // trim(level_name), new_grid%nCells)

    allocate(new_grid%mask(new_grid%nrows, new_grid%ncols))
    allocate(new_grid%x(new_grid%nrows, new_grid%ncols))
    allocate(new_grid%y(new_grid%nrows, new_grid%ncols))
    ! read L1 mask
    var = nc%getVariable("L" // trim(level_name) // "_basin_mask")
    ! read integer
    call var%getData(dummyI2)
    ! transform to logical
    new_grid%mask = (dummyI2 .eq. 1_i4)

    var = nc%getVariable("L" // trim(level_name) // "_basin_lat")
    call var%getData(new_grid%y)

    var = nc%getVariable("L" // trim(level_name) // "_basin_lon")
    call var%getData(new_grid%x)

    var = nc%getVariable("L" // trim(level_name) // "_basin_cellarea")
    call var%getData(dummyD2)
    new_grid%CellArea = pack(dummyD2 / 1.0E-6_dp, new_grid%mask)

    call nc%close()

    new_grid%Id = (/ (k, k = 1, new_grid%nCells) /)

  end subroutine read_grid_info

end module mo_common_restart


