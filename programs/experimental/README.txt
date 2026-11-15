CHKDSK.ASM is kept here, not shipped in the image.
It computes the geometry and label correctly, but its FAT scan sometimes
spins forever depending on where the kernel lands in memory - an
uninitialised-variable bug I have not pinned down yet.
