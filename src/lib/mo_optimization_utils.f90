module mo_optimization_utils

  use mo_kind, only : dp

  implicit none

  abstract interface
    subroutine eval_interface(parameterset, opti_domain_indices, runoff, sm_opti, domain_avg_tws, neutrons_opti, et_opti)
      use mo_kind, only : dp, i4
      real(dp),    dimension(:), intent(in) :: parameterset
      integer(i4), dimension(:),                 optional, intent(in)  :: opti_domain_indices
      real(dp),    dimension(:, :), allocatable, optional, intent(out) :: runoff        ! dim1=time dim2=gauge
      real(dp),    dimension(:, :), allocatable, optional, intent(out) :: sm_opti       ! dim1=ncells, dim2=time
      real(dp),    dimension(:, :), allocatable, optional, intent(out) :: domain_avg_tws ! dim1=time dim2=nDomains
      real(dp),    dimension(:, :), allocatable, optional, intent(out) :: neutrons_opti ! dim1=ncells, dim2=time
      real(dp),    dimension(:, :), allocatable, optional, intent(out) :: et_opti       ! dim1=ncells, dim2=time
    end subroutine
  end interface

  interface
    function objective_interface (parameterset, eval, arg1, arg2, arg3)
      use mo_kind, only : dp
      import eval_interface
      real(dp), intent(in), dimension(:) :: parameterset
      procedure(eval_interface), INTENT(IN), pointer :: eval
      real(dp), optional, intent(in) :: arg1
      real(dp), optional, intent(out) :: arg2
      real(dp), optional, intent(out) :: arg3

      real(dp) :: objective_interface
    end function objective_interface
  end interface

end module mo_optimization_utils


