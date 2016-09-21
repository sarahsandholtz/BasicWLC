subroutine initial_methyl_profile(nt,meth_status,nuc_site)
    implicit none
    integer, intent(in) :: nt
    integer, intent(inout) :: meth_status(nt), nuc_site
    integer :: i

    nuc_site = ceiling(real(nt/2.0))

    do i = 1, nt
        meth_status(i) = 1
    end do

    
end 
   
     
    
 
