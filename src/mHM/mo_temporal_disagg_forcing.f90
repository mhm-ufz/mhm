!>       \file mo_temporal_disagg_forcing.f90

!>       \brief Temporal disaggregation of daily input values

!>       \details Calculate actual values for precipitation, PET and temperature from daily mean inputs
!>       ote There is not PET correction for aspect in this routine. Use pet * fasp before or after the routine.

!>       \authors Matthias Cuntz

!>       \date Dec 2012

! Modifications:

MODULE mo_temporal_disagg_forcing

  USE mo_kind, ONLY : dp

  IMPLICIT NONE

  PRIVATE

  PUBLIC :: temporal_disagg_forcing ! Temporally distribute forcings onto time step
  PUBLIC :: temporal_disagg_temperature ! Temporally distribute temperature onto time step

  ! ------------------------------------------------------------------

CONTAINS

  ! ------------------------------------------------------------------

  !    NAME
  !        temporal_disagg_forcing

  !    PURPOSE
  !>       \brief Temporally distribute daily mean forcings onto time step

  !>       \details Calculates actual precipitation, PET and temperature from daily mean inputs.
  !>       Precipitation and PET are distributed with predefined factors onto the day.
  !>       Temperature gets a predefined amplitude added on day and substracted at night.
  !>       Alternatively, weights for each hour and month can be given and disaggregation is
  !>       using these as factors for PET and temperature. Precipitation is distributed uniformly.

  !    INTENT(IN)
  !>       \param[in] "logical :: isday"              is day or night
  !>       \param[in] "real(dp) :: ntimesteps_day"    # of time steps per day
  !>       \param[in] "real(dp) :: prec_day"          Daily mean precipitation [mm/s]
  !>       \param[in] "real(dp) :: pet_day"           Daily mean ET [mm/s]
  !>       \param[in] "real(dp) :: temp_day"          Daily mean air temperature [K]
  !>       \param[in] "real(dp) :: fday_prec"         Daytime fraction of precipitation
  !>       \param[in] "real(dp) :: fday_pet"          Daytime fraction of PET
  !>       \param[in] "real(dp) :: fday_temp"         Daytime air temparture increase
  !>       \param[in] "real(dp) :: fnight_prec"       Daytime fraction of precipitation
  !>       \param[in] "real(dp) :: fnight_pet"        Daytime fraction of PET
  !>       \param[in] "real(dp) :: fnight_temp"       Daytime air temparture increase
  !>       \param[in] "real(dp) :: temp_weights"      weights for average temperature
  !>       \param[in] "real(dp) :: pet_weights"       weights for PET
  !>       \param[in] "real(dp) :: pre_weights"       weights for precipitation
  !>       \param[in] "logical :: read_meteo_weights" flag indicating that weights should be used

  !    INTENT(OUT)
  !>       \param[out] "real(dp) :: prec" Actual precipitation [mm/s]
  !>       \param[out] "real(dp) :: pet"  Reference ET [mm/s]
  !>       \param[out] "real(dp) :: temp" Air temperature [K]

  !    HISTORY
  !>       \authors Matthias Cuntz

  !>       \date Dec 2012

  ! Modifications:
  ! S. Thober Jan 2017 - > added disaggregation based on weights given in nc file
  ! Robert Schweppe Jun 2018 - refactoring and reformatting

  elemental pure subroutine temporal_disagg_forcing( &
      isday, ntimesteps_day, &
      prec_day, pet_day, temp_day, &
      fday_prec, fday_pet, fday_temp, &
      fnight_prec, fnight_pet, fnight_temp, &
      temp_weights, pet_weights, pre_weights, read_meteo_weights, &
      prec, pet, temp &
  )
    implicit none

    ! is day or night
    logical, intent(in) :: isday
    ! # of time steps per day
    real(dp), intent(in) :: ntimesteps_day
    ! Daily mean precipitation [mm/s]
    real(dp), intent(in) :: prec_day
    ! Daily mean ET [mm/s]
    real(dp), intent(in) :: pet_day
    ! Daily mean air temperature [K]
    real(dp), intent(in) :: temp_day
    ! Daytime fraction of precipitation
    real(dp), intent(in) :: fday_prec
    ! Daytime fraction of PET
    real(dp), intent(in) :: fday_pet
    ! Daytime air temparture increase
    real(dp), intent(in) :: fday_temp
    ! Daytime fraction of precipitation
    real(dp), intent(in) :: fnight_prec
    ! Daytime fraction of PET
    real(dp), intent(in) :: fnight_pet
    ! Daytime air temparture increase
    real(dp), intent(in) :: fnight_temp
    ! weights for average temperature
    real(dp), intent(in) :: temp_weights
    ! weights for PET
    real(dp), intent(in) :: pet_weights
    ! weights for precipitation
    real(dp), intent(in) :: pre_weights
    ! flag indicating that weights should be used
    logical, intent(in) :: read_meteo_weights
    ! Actual precipitation [mm/s]
    real(dp), intent(out) :: prec
    ! Reference ET [mm/s]
    real(dp), intent(out) :: pet
    ! Air temperature [K]
    real(dp), intent(out) :: temp

    ! default vaule used if ntimesteps_day = 1 (i.e., e.g. daily values)
    prec = prec_day
    pet = pet_day
    ! use separate disaggregation subroutine for temperature
    call temporal_disagg_temperature(&
        isday, ntimesteps_day, &
        temp_day, fday_temp, fnight_temp, &
        temp_weights, read_meteo_weights, &
        temp &
    )
    if (read_meteo_weights) then
      ! apply weights
      pet = pet * pet_weights
      prec = prec * pre_weights
    else
      ! Distribute Prec, PET and Temp into time steps night/day
      if(ntimesteps_day .gt. 1.0_dp) then
        if (isday) then ! DAY-TIME
          prec = 2.0_dp * prec_day * fday_prec / ntimesteps_day
          pet = 2.0_dp * pet_day * fday_pet / ntimesteps_day
        else            ! NIGHT-TIME
          prec = 2.0_dp * prec_day * fnight_prec / ntimesteps_day
          pet = 2.0_dp * pet_day * fnight_pet / ntimesteps_day
        end if
      end if
    end if

  end subroutine temporal_disagg_forcing

  elemental pure subroutine temporal_disagg_temperature(&
      isday, ntimesteps_day, &
      temp_day, fday_temp, fnight_temp, &
      temp_weights, read_meteo_weights, &
      temp &
  )
    use mo_constants, only : T0_dp  ! 273.15 - Celcius <-> Kelvin [K]

    implicit none

    ! is day or night
    logical, intent(in) :: isday
    ! # of time steps per day
    real(dp), intent(in) :: ntimesteps_day
    ! Daily mean air temperature [K]
    real(dp), intent(in) :: temp_day
    ! Daytime air temparture increase
    real(dp), intent(in) :: fday_temp
    ! Daytime air temparture increase
    real(dp), intent(in) :: fnight_temp
    ! weights for average temperature
    real(dp), intent(in) :: temp_weights
    ! flag indicating that weights should be used
    logical, intent(in) :: read_meteo_weights
    ! Air temperature [K]
    real(dp), intent(out) :: temp


    ! default vaule used if ntimesteps_day = 1 (i.e., e.g. daily values)
    temp = temp_day

    if (read_meteo_weights) then
      ! apply weights
      temp = (temp + T0_dp) * temp_weights - T0_dp ! temperature weights are in K
    else
      ! Distribute Temp into time steps night/day
      if(ntimesteps_day .gt. 1.0_dp) then
        if (isday) then ! DAY-TIME
          temp = temp_day + fday_temp
        else            ! NIGHT-TIME
          temp = temp_day + fnight_temp
        end if
      end if
    end if

  end subroutine temporal_disagg_temperature

END MODULE mo_temporal_disagg_forcing
