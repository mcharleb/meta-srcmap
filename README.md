# meta-srcmap

A class for OE/Yocto to enable code scanning for license scans etc.
It was designed to work with the LiD license scanner, but could be used
with any code scanner.

## Configuration

Add meta-srcmap to your bblayers.conf

Add the following to your local.conf when BUILDDIR is defined in your environment:

```
scripts/enable-srcmap.sh

```
That will create ${BUILDDIR}/srcmap-output if SRCMAPSPKGDIR is not set and will set
SRCMAPSPKGDIR=${BUILDDIR}/srcmap-output.

The srcmap class will also create archives of the unpatched, extracted, downloaded source under
${SRCMAPSPKGDIR}/extracted_sources
