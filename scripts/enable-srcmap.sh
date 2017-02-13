#!/bin/bash
grep 'SRCMAPSPKGDIR"' ${BUILDDIR}/conf/local.conf || (mkdir -p ${BUILDDIR}/srcmap-output && echo 'SRCMAPSPKGDIR ?= "${TOPDIR}/srcmap-output"' >> ${BUILDDIR}/conf/local.conf )
grep 'INHERIT += "srcmap"' ${BUILDDIR}/conf/local.conf || (echo 'INHERIT += "srcmap"' >> ${BUILDDIR}/conf/local.conf )
grep 'meta-srcmap' ${BUILDDIR}/conf/bblayers.conf || (echo 'BBLAYERS += "${TOPDIR}/../poky/meta-srcmap "' >> ${BUILDDIR}/conf/bblayers.conf )
