!>       \file mo_read_spatial_data.f90

!>       \brief Reads spatial input data.

!>       \details This module is to read spatial input data, e.g. dem, aspect, flow direction.
!>       The module provides a subroutine for ASCII files.
!>       (Subroutine for NetCDF files will come with release 5.1).
!>       The data are read from the specified directory.

!>       \authors Juliane Mai

!>       \date Dec 2012

! Modifications:

MODULE mo_read_spatial_data

  ! This module provides routines to read spatial data.

  ! Written  Juliane Mai, Jan 2013
  ! Modified 

  USE mo_kind, ONLY : i4, dp
  USE mo_os, ONLY : path_isfile

  IMPLICIT NONE

  PUBLIC :: read_header_ascii           ! Reads header of ASCII files
  PUBLIC :: read_spatial_data_ascii     ! Read ASCII  files
  ! PUBLIC :: read_spatial_data_nc      ! Read netCDF files -> will be implemented in release 5.1

  ! ------------------------------------------------------------------

  !    NAME
  !        read_spatial_data_ascii

  !    PURPOSE
  !>       \brief Reads spatial data files of ASCII format.

  !>       \details Reads spatial input data, e.g. dem, aspect, flow direction.

  !    HISTORY
  !>       \authors Juliane Mai

  !>       \date Jan 2013

  ! Modifications:
  ! Matthias Zink  Feb 2013 - , added interface and routine for datatype i4
  ! David Schaefer Mar 2015 - , removed double allocation of temporary data
  ! Robert Schweppe Jun 2018 - refactoring and reformatting

  INTERFACE  read_spatial_data_ascii
    MODULE PROCEDURE read_spatial_data_ascii_i4, read_spatial_data_ascii_dp
  END INTERFACE read_spatial_data_ascii

  ! ------------------------------------------------------------------

  PRIVATE

  ! ------------------------------------------------------------------

CONTAINS

  ! ------------------------------------------------------------------

  !    NAME
  !        read_spatial_data_ascii_dp

  !    PURPOSE
  !>       \brief TODO: add description

  !>       \details TODO: add description

  !    INTENT(IN)
  !>       \param[in] "character(len = *) :: filename" filename with location
  !>       \param[in] "integer(i4) :: fileunit"        unit for opening the file
  !>       \param[in] "integer(i4) :: header_nCols"    number of columns of data fields:
  !>       \param[in] "integer(i4) :: header_nRows"    number of rows of data fields:
  !>       \param[in] "real(dp) :: header_xllcorner"   header read in lower left corner
  !>       \param[in] "real(dp) :: header_yllcorner"   header read in lower left corner
  !>       \param[in] "real(dp) :: header_cellsize"    header read in cellsize

  !    INTENT(OUT)
  !>       \param[out] "real(dp), dimension(:, :) :: data" data
  !>       \param[out] "logical, dimension(:, :) :: mask"  mask

  !    HISTORY
  !>       \authors Robert Schweppe

  !>       \date Jun 2018

  ! Modifications:

  subroutine read_spatial_data_ascii_dp(filename, fileunit, header_ncols, header_nrows, header_xllcorner, &
                                       header_yllcorner, header_cellsize, data, mask)
    implicit none

    ! filename with location
    character(len = *), intent(in) :: filename

    ! unit for opening the file
    integer(i4), intent(in) :: fileunit

    ! number of rows of data fields:
    integer(i4), intent(in) :: header_nRows

    ! number of columns of data fields:
    integer(i4), intent(in) :: header_nCols

    ! header read in lower left corner
    real(dp), intent(in) :: header_xllcorner

    ! header read in lower left corner
    real(dp), intent(in) :: header_yllcorner

    ! header read in cellsize
    real(dp), intent(in) :: header_cellsize

    ! data
    real(dp), dimension(:, :), allocatable, intent(out) :: data

    ! mask
    logical, dimension(:, :), allocatable, intent(out) :: mask

    ! number of rows of data fields:
    integer(i4) :: file_nRows

    ! number of columns of data fields:
    integer(i4) :: file_nCols

    ! file read in lower left corner
    real(dp) :: file_xllcorner

    ! file read in lower left corner
    real(dp) :: file_yllcorner

    ! file read in cellsize
    real(dp) :: file_cellsize

    ! file read in nodata value
    real(dp) :: file_nodata

    integer(i4) :: i, j


    ! compare headers always with reference header (intent in)
    call read_header_ascii(filename, fileunit, &
            file_ncols, file_nrows, &
            file_xllcorner, file_yllcorner, file_cellsize, file_nodata)
    if ((file_ncols .ne. header_ncols)) &
            stop 'read_spatial_data_ascii: header not matching with reference header: ncols'
    if ((file_nrows .ne. header_nrows)) &
            stop 'read_spatial_data_ascii: header not matching with reference header: nrows'
    if ((abs(file_xllcorner - header_xllcorner) .gt. tiny(1.0_dp))) &
            stop 'read_spatial_data_ascii: header not matching with reference header: xllcorner'
    if ((abs(file_yllcorner - header_yllcorner) .gt. tiny(1.0_dp))) &
            stop 'read_spatial_data_ascii: header not matching with reference header: yllcorner'
    if ((abs(file_cellsize - header_cellsize)   .gt. tiny(1.0_dp))) &
            stop 'read_spatial_data_ascii: header not matching with reference header: cellsize'

    ! allocation and initialization of matrices
    allocate(data(file_ncols, file_nrows))
    data = file_nodata
    allocate(mask(file_ncols, file_nrows))
    mask = .true.
    
    !checking whether the file exists
    call path_isfile(path = filename, quiet_ = .true., throwError_ = .true.)
    ! read in
    ! recl is only a rough estimate on bytes per line in the ascii
    ! default for nag: recl=1024(byte) which is not enough for 100s of columns
    open (unit = fileunit, file = filename, action = 'read', status = 'old', recl = 48 * file_ncols)
    ! (a) skip header
    do i = 1, 6
      read(fileunit, *)
    end do
    ! (b) read data
    do i = 1, file_nrows
      ! read(fileunit, *) (tmpdata(i, j), j = 1, file_ncols)
      read(fileunit, *) (data(j, file_nrows - i + 1), j = 1, file_ncols)
    end do
    close(fileunit)

    ! set mask .false. if nodata value appeared
    where (abs(data - file_nodata) < tiny(1.0_dp))
      mask = .false.
    end where


  end subroutine read_spatial_data_ascii_dp

  !    NAME
  !        read_spatial_data_ascii_i4

  !    PURPOSE
  !>       \brief TODO: add description

  !>       \details TODO: add description

  !    INTENT(IN)
  !>       \param[in] "character(len = *) :: filename" filename with location
  !>       \param[in] "integer(i4) :: fileunit"        unit for opening the file
  !>       \param[in] "integer(i4) :: header_nCols"    number of columns of data fields:
  !>       \param[in] "integer(i4) :: header_nRows"    number of rows of data fields:
  !>       \param[in] "real(dp) :: header_xllcorner"   header read in lower left corner
  !>       \param[in] "real(dp) :: header_yllcorner"   header read in lower left corner
  !>       \param[in] "real(dp) :: header_cellsize"    header read in cellsize

  !    INTENT(OUT)
  !>       \param[out] "integer(i4), dimension(:, :) :: data" data
  !>       \param[out] "logical, dimension(:, :) :: mask"     mask

  !    HISTORY
  !>       \authors Robert Schweppe

  !>       \date Jun 2018

  ! Modifications:

  subroutine read_spatial_data_ascii_i4(filename, fileunit, header_ncols, header_nrows, header_xllcorner, &
                                       header_yllcorner, header_cellsize, data, mask)
    implicit none

    ! filename with location
    character(len = *), intent(in) :: filename

    ! unit for opening the file
    integer(i4), intent(in) :: fileunit

    ! number of rows of data fields:
    integer(i4), intent(in) :: header_nRows

    ! number of columns of data fields:
    integer(i4), intent(in) :: header_nCols

    ! header read in lower left corner
    real(dp), intent(in) :: header_xllcorner

    ! header read in lower left corner
    real(dp), intent(in) :: header_yllcorner

    ! header read in cellsize
    real(dp), intent(in) :: header_cellsize

    ! data
    integer(i4), dimension(:, :), allocatable, intent(out) :: data

    ! mask
    logical, dimension(:, :), allocatable, intent(out) :: mask

    ! number of rows of data fields:
    integer(i4) :: file_nRows

    ! number of columns of data fields:
    integer(i4) :: file_nCols

    ! file read in lower left corner
    real(dp) :: file_xllcorner

    ! file read in lower left corner
    real(dp) :: file_yllcorner

    ! file read in cellsize
    real(dp) :: file_cellsize

    ! file read in nodata value
    real(dp) :: file_nodata

    integer(i4) :: i, j


    ! compare headers always with reference header (intent in)
    call read_header_ascii(filename, fileunit, &
            file_ncols, file_nrows, &
            file_xllcorner, file_yllcorner, file_cellsize, file_nodata)
    if ((file_ncols .ne. header_ncols)) &
            stop 'read_spatial_data_ascii: header not matching with reference header: ncols'
    if ((file_nrows .ne. header_nrows)) &
            stop 'read_spatial_data_ascii: header not matching with reference header: nrows'
    if ((abs(file_xllcorner - header_xllcorner) .gt. tiny(1.0_dp))) &
            stop 'read_spatial_data_ascii: header not matching with reference header: xllcorner'
    if ((abs(file_yllcorner - header_yllcorner) .gt. tiny(1.0_dp))) &
            stop 'read_spatial_data_ascii: header not matching with reference header: yllcorner'
    if ((abs(file_cellsize - header_cellsize)   .gt. tiny(1.0_dp))) &
            stop 'read_spatial_data_ascii: header not matching with reference header: cellsize'

    ! allocation and initialization of matrices
    allocate(data(file_ncols, file_nrows))
    data = int(file_nodata, i4)
    allocate(mask(file_ncols, file_nrows))
    mask = .true.

    !checking whether the file exists
    call path_isfile(path = filename, quiet_ = .true., throwError_ = .true.)
    ! read in
    ! recl is only a rough estimate on bytes per line in the ascii
    ! default for nag: recl=1024(byte) which is not enough for 100s of columns
    open (unit = fileunit, file = filename, action = 'read', status = 'old', recl = 48 * file_ncols)
    ! (a) skip header
    do i = 1, 6
      read(fileunit, *)
    end do
    ! (b) read data
    do i = 1, file_nrows
      read(fileunit, *) (data(j, file_nrows - i + 1), j = 1, file_ncols)
    end do
    close(fileunit)

    ! set mask .false. if nodata value appeared
    where (data == int(file_nodata, i4))
      mask = .false.
    end where


  end subroutine read_spatial_data_ascii_i4

  ! ------------------------------------------------------------------

  !    NAME
  !        read_header_ascii

  !    PURPOSE
  !>       \brief Reads header lines of ASCII files.

  !>       \details Reads header lines of ASCII files, e.g. dem, aspect, flow direction.

  !    INTENT(IN)
  !>       \param[in] "character(len = *) :: filename" Name of file and its location
  !>       \param[in] "integer(i4) :: fileunit"        File unit for open file

  !    INTENT(OUT)
  !>       \param[out] "integer(i4) :: header_nCols"  Reference number of columns
  !>       \param[out] "integer(i4) :: header_nRows"  Reference number of rows
  !>       \param[out] "real(dp) :: header_xllcorner" Reference lower left corner (x)
  !>       \param[out] "real(dp) :: header_yllcorner" Reference lower left corner (y)
  !>       \param[out] "real(dp) :: header_cellsize"  Reference cell size [m]
  !>       \param[out] "real(dp) :: header_nodata"    Reference nodata value

  !    HISTORY
  !>       \authors Juliane Mai

  !>       \date Jan 2013

  ! Modifications:
  ! Robert Schweppe Jun 2018 - refactoring and reformatting

  subroutine read_header_ascii(filename, fileunit, header_ncols, header_nrows, header_xllcorner, header_yllcorner, &
                              header_cellsize, header_nodata)
    implicit none

    ! Name of file and its location
    character(len = *), intent(in) :: filename

    ! File unit for open file
    integer(i4), intent(in) :: fileunit

    ! Reference number of rows
    integer(i4), intent(out) :: header_nRows

    ! Reference number of columns
    integer(i4), intent(out) :: header_nCols

    ! Reference lower left corner (x)
    real(dp), intent(out) :: header_xllcorner

    ! Reference lower left corner (y)
    real(dp), intent(out) :: header_yllcorner

    ! Reference cell size [m]
    real(dp), intent(out) :: header_cellsize

    ! Reference nodata value
    real(dp), intent(out) :: header_nodata

    character(5) :: dummy


    !checking whether the file exists
    call path_isfile(path = filename, quiet_ = .true., throwError_ = .true.)
    ! reading header from a file
    open (unit = fileunit, file = filename, status = 'old')
    read (fileunit, *) dummy, header_nCols
    read (fileunit, *) dummy, header_nRows
    read (fileunit, *) dummy, header_xllcorner
    read (fileunit, *) dummy, header_yllcorner
    read (fileunit, *) dummy, header_cellsize
    read (fileunit, *) dummy, header_nodata
    close(fileunit)
    dummy = dummy // ''   ! only to avoid warning

  end subroutine read_header_ascii

END MODULE mo_read_spatial_data
