# This class generates files describing the locations of all source files used
# to build a target and its package dependencies.

inherit patch

python() {
    pn = d.getVar('PN', True)
    assume_provided = (d.getVar("ASSUME_PROVIDED", True) or "").split()
    if pn in assume_provided:
        for p in d.getVar("PROVIDES", True).split():
            if p != pn:
                pn = p
                break

    d.appendVarFlag('do_srcmap_deploy', 'depends', ' %s:do_srcmap_patch' % pn)
}

python do_srcmap_patch () {
    import whatthepatch

    src_uri = (d.getVar('SRC_URI', True) or "").split()
    sourcedir = d.getVar('S', True)
    workdir = d.getVar('WORKDIR', True)

    # Only scan the patched files
    (pkgfile_list, depuri_list, patch_list) = segment_uris(d, src_uri)

    # patch_list entries are in the form (URI, filepath)
    patched_files = []
    for p in patch_list:
        #bb.warn("PATCH: "+p[1])
        founddiff = 0;

        patchdata = ""
        try: 
            patch = whatthepatch.parse_patch(open(p[1], "r").read())
        except ValueError as e:
            try:
                bb.warn("Trying unicode_escape codec for :"+p[1])
                patch = whatthepatch.parse_patch(open(p[1], "r", encoding='unicode_escape').read())
            except ValueError as e:
                bb.fatal("Unable to decode patch file: "+p[1])

        for diff in patch:                
            pname = diff.header.new_path
            #bb.warn("PATCH PATH: " + pname)
            if len(p[0].split(";")) > 1:
                bb.warn("PATCH URIDATA: " + p[0])
            if not os.path.isfile(os.path.join(sourcedir, pname)):
                path_elements = pname.split(os.path.sep)[1:]
                if len(path_elements) > 1:
                    pname = os.path.join(*path_elements)
                elif len(path_elements) == 1:
                    pname = path_elements[0]
            if pname not in patched_files:
                patched_files.append(pname)
                realfile = os.path.join(sourcedir, pname)
                if not os.path.isfile(realfile):
                    bb.warn("Patched file not found: "+realfile )


    #bb.warn("PATCHEDFILES: "+" ".join(patched_files))

    #for file in patched_files:
    #    # TODO scan the patched files and add to package report

    provides_unpacked_src = src_provider_check(workdir, sourcedir)

    # Update the package
    process_package_update(d, provides_unpacked_src, patched_files)
}

python do_srcmap_unpack () {
    workdir = d.getVar('WORKDIR', True)
    sourcedir = d.getVar('S', True)

    pkgfile_list = []
    patch_list = []
    depuri_list = []
    depfile_list = []
    unresolved_src_dir = ""
    provides_unpacked_src = ""

    # packages like libgcc use a shared workdir
    src_uri = (d.getVar('SRC_URI', True) or "").split()
    if not sourcedir.startswith(workdir):
        # There is no unpack dep on other packages so provider may not have been scanned
        unresolved_src_dir = sourcedir
    else:
        # If no SRC_URI and not using external src
        if len(src_uri) == 0:
            pn = d.getVar('PN', True)
            bb.warn("No source for "+pn)
            process_package(d, provides_unpacked_src, pkgfile_list, depfile_list, unresolved_src_dir)
            return

    provides_unpacked_src = src_provider_check(workdir, sourcedir)

    (pkgfile_list, depuri_list, patch_list) = segment_uris(d, src_uri)

    # Find unpack dirs for DEPURI_LIST
    depfile_list = process_dependencies(d, depuri_list, workdir, sourcedir)

    process_package(d, provides_unpacked_src, pkgfile_list, depfile_list, unresolved_src_dir)

    return
}

def src_provider_check(workdir, sourcedir):
    provides_unpacked_src = ""

    # Packages like gcc-source create a shared source directory
    if "work-shared" in workdir:
        if sourcedir.startswith(workdir):
            provides_unpacked_src = sourcedir
            #bb.warn("SHARED SOURCE DIR: " + provides_unpacked_src)
        else:
            bb.warn("ERROR - unable to determine shared src dir: " + workdir + " " + sourcedir)

    return provides_unpacked_src

def segment_uris(d, src_uri):
    file_dirname = d.getVar('FILE_DIRNAME', True)

    pkgfile_list = []
    patch_list = []
    depuri_list = []
    patches = src_patches(d)
    fetch = bb.fetch2.Fetch([], d)
    for uri in src_uri:
        local = fetch.localpath(uri)
        if "file://"+local not in [ x.split(";")[0] for x in patches ]:
            if local.startswith(file_dirname):
                pkgfile_list.append((uri, local))
            else:
                depuri_list.append((uri, local))
        else:
            patch_list.append((uri, local))

    #bb.warn("PKGFILE_LIST: " + " ".join([ x[0]+" "+x[1] for x in pkgfile_list ]))
    #bb.warn("PATCH_LIST: " + " ".join([ x[0]+" "+x[1] for x in patch_list ]))
    #bb.warn("DEPURI_LIST: " + " ".join([ x[0]+" "+x[1] for x in depuri_list ]))

    return (pkgfile_list, depuri_list, patch_list)

def process_dependencies(d, depuri_list, workdir, sourcedir):
    import json
    import codecs

    spkgdir = d.getVar('SRCMAPSPKGDIR', True)
    file_dirname = d.getVar('FILE_DIRNAME', True)

    depfile_list = []
    for dep in depuri_list:
        uri = dep[0]
        localfile = dep[1].rstrip("/")
        bname = os.path.split(localfile)[1]

        #unpackuri = ""
        archiveuri = ""
        srcmapfile = os.path.join(spkgdir, bname, ".srcmap")
        if os.path.isfile(srcmapfile):
            with codecs.open(srcmapfile, mode='r', encoding='utf-8') as f:
                srcmapdoc = json.load(f)
                if srcmapdoc['URI'] == uri:
                    depfile_list.append((uri, srcmapfile))
                    continue

        #dname = os.path.join(spkgdir,"extracted_src", bname)
        dname_extracted = os.path.join(spkgdir,"extracted_src", bname)
        dname = os.path.join(spkgdir,"archived_src")
        if not os.path.isdir(dname):
            os.makedirs(dname)
        dname_archived = os.path.join(dname, bname)
        
        dname_archived_done = dname_archived+".done"
        dname_extracted_done = dname_extracted+".done"
        if os.path.isfile(localfile):
            from pathlib import Path

            archiveuri = localfile

            if not os.path.exists(dname_extracted_done):
                # Unpack the source to a separate dir to enable do_patch to proceed
                fetcher = bb.fetch2.Fetch([ uri ], d)
                bb.warn("Saving unpatched src in: %s " % dname_extracted)
                if not os.path.exists(dname_extracted):
                    os.makedirs(dname_extracted)
                fetcher.unpack(dname_extracted)
                Path(dname_extracted_done).touch()

        elif os.path.isdir(localfile):
            import shutil
            import tarfile

            archiveuri = dname_archived+".tar.gz"
            if not os.path.exists(dname_archived_done):
                tar = tarfile.open(archiveuri, 'w:gz')
                tar.add(localfile, arcname=os.path.basename(localfile))
                tar.close()

            dname_extracted = localfile
                
        #unpackuri = dname
            
        pn = d.getVar('PN', True)
        pv = d.getVar('PV', True)
        #bb.warn("FOUND: "+unpackuri)
        srcmapdoc = {}
        srcmapdoc['URI'] = uri
        srcmapdoc['Packagename'] = localfile
        #srcmapdoc['Source'] = unpackuri
        srcmapdoc['Source'] = archiveuri
        srcmapdoc['ExtractedDir'] = dname_extracted
        #srcmapdoc['Name'] = bname.split("-")[0].split(".")[0]
        srcmapdoc['UsedBy'] = [ pn+"-"+pv ] 

        srcmapfile = os.path.join(spkgdir, bname+".srcmap")
        with codecs.open(srcmapfile, mode='w', encoding='utf-8') as f:
            f.write(json.dumps(srcmapdoc, indent=4))
        depfile_list.append((uri, srcmapfile))

    return depfile_list

def provides_shared_source(srcpath, spkgdir):
    import json
    import codecs
    import glob

    #bb.warn("LOOKING FOR PROVIDER FOR: "+srcpath)
    # Find that package that provides the shared src
    for srcmapfile in glob.glob(os.path.join(spkgdir, "*-export.smpkg")):
        if os.path.isfile(srcmapfile):
            with codecs.open(srcmapfile, mode='r', encoding='utf-8') as f:
                srcmapdoc = json.load(f)
                #bb.warn(srcmapfile +" ProvidesSource="+srcmapdoc['ProvidesSource'])
                if srcmapdoc['ProvidesSource'] == srcpath:
                    bb.warn("FOUND PROFIDER FOR: "+srcpath+" "+srcmapfile)
                    return srcmapfile
    bb.warn("ERROR - provider not found for: "+srcpath)
    return ""

def process_package(d, provides_unpacked_src, package_uri_list, depfile_list, unresolved_src_dir):
    import json
    import codecs

    bb.warn("PROCESS PACKAGE");
    sourcedir = d.getVar('S', True)
    file_dirname = d.getVar('FILE_DIRNAME', True)
    pkglicense = d.getVar('LICENSE', True)
    pkglicensechksum = d.getVar('LIC_FILES_CHKSUM', True)
    packages = (d.getVar('PACKAGES', True) or "").split()
    spkgdir = d.getVar('SRCMAPSPKGDIR', True)
    image_install = d.getVar('IMAGE_INSTALL', True)
    provides = (d.getVar('PROVIDES', True) or "").split()
    depends = (d.getVar('DEPENDS', True) or "").split()
    pn = d.getVar('PN', True)
    pv = d.getVar('PV', True)

    rdeps = {}
    for p in packages:
        deps = d.getVar("RDEPENDS_"+p, True)
        if deps:
            rdeps[p] = deps
        
    srcmap_doc = {}
    (name, fname) = get_full_package_filename(d, provides_unpacked_src)
    srcmap_doc['Name'] = name
    srcmap_doc['PN'] = pn
    srcmap_doc['PV'] = pv
    srcmap_doc['Files'] = package_uri_list
    srcmap_doc['SourceDir'] = sourcedir
    srcmap_doc['DownloadURIs'] = depfile_list
    if unresolved_src_dir:
        srcmap_doc['UnresolvedSrcDir'] = unresolved_src_dir
    srcmap_doc['Dirname'] = file_dirname
    if image_install:
        srcmap_doc['ImagePackages'] = image_install
    srcmap_doc['PACKAGES'] = packages
    srcmap_doc['LICENSE'] = pkglicense
    srcmap_doc['DEPENDS'] = depends
    srcmap_doc['RDEPENDS'] = rdeps
    srcmap_doc['PROVIDES'] = provides

    if provides_unpacked_src:
        srcmap_doc['ProvidesSource'] = provides_unpacked_src

    bb.warn("Writing to "+fname)
    with codecs.open(fname, mode='w', encoding='utf-8') as f:
        f.write(json.dumps(srcmap_doc, indent=4))

def process_package_update(d, provides_unpacked_src, patched_files):
    import json
    import codecs

    spkgdir = d.getVar('SRCMAPSPKGDIR', True)

    srcmapdoc = None
    (name, fname) = get_full_package_filename(d, provides_unpacked_src)
    if os.path.exists(fname):
        with codecs.open(fname, mode='r', encoding='utf-8') as f:
            try:
                srcmapdoc = json.load(f)

            except ValueError as e:
                bb.fatal("SRCMAP: Failed to read " + fname)
    else:
        bb.fatal("SRCMAP: could not find " + fname)

    srcmapdoc['PatchedFiles'] = patched_files
    
    with codecs.open(fname, mode='w', encoding='utf-8') as f:
        f.write(json.dumps(srcmapdoc, indent=4))
    
def get_full_package_filename(d, provides_unpacked_src):
    pn = d.getVar('PN', True)
    pv = d.getVar('PV', True)
    package_arch = d.getVar('PACKAGE_ARCH', True)
    spkgdir = d.getVar('SRCMAPSPKGDIR', True)
    name = pn + "-" + pv + "-" + package_arch
    extension = ".smpkg"
    if provides_unpacked_src:
        extension = "-export.smpkg"
    return (name, os.path.join(spkgdir, name + extension))

def process_src_uri(d, uri_data):
    import json
    import codecs

    bb.warn("Processing : " + uri_data[0])
    info = {}
    for f in uri_data:
        #bb.warn("URIDATA: " + f)
        data = f.split("downloadfilename=")
        subdir = f.split("subdir=")
        if len(data) > 1:
            info['downloadfilename'] = data[1]
        if len(subdir) > 1:
            info['subdir'] = subdir[1]
    src_package = uri_data[0]
    
    info['sourcedir'] = d.getVar('S', True)
    info['srcrev'] = d.getVar('SRCREV', True)
    info['dl_dir'] = d.getVar('DL_DIR', True)
    pn = d.getVar('PN', True)
    pv = d.getVar('PV', True)

    info['workdir'] = d.getVar('WORKDIR', True)
    package_arch = d.getVar('PACKAGE_ARCH', True)
    spkgdir = d.getVar('SRCMAPSPKGDIR', True)
    #bb.warn("SRCMAPSPKGDIR: " + spkgdir)
    #bb.warn("src_package: " + src_package)
    #bb.warn("S: " + info['sourcedir'])
    #if info['srcrev'] != "INVALID":
        #bb.warn("SRCREV: " + info['srcrev'])

    pkgfname = src_package.split("/")[-1]
    if 'downloadfilename' in info:
        pkgfname = info['downloadfilename']

    srcdirname = src_package.split("/")[-1]
    if 'subdir' in info:
        srcdirname = os.path.join(info['workdir'],info['subdir'])
        # TODO find downloaded src location for uri

    fname = os.path.join(spkgdir, pkgfname + ".srcmap")

    pkgname = pn + "-" + pv + "-" + package_arch

    srcmapdoc = None
    if os.path.exists(fname):
        with codecs.open(fname, mode='r', encoding='utf-8') as f:
            try:
                srcmapdoc = json.load(f)
                #bb.warn("SRCMAP: linking " + fname + " to " + pkgname)

            except ValueError as e:
                bb.warn("SRCMAP: Failed to read " + fname)

    if srcmapdoc == None:

        srcmapdoc = {}
        srcmapdoc['FileName'] = pkgfname

        srcmapdoc['Name'] = srcmapdoc['FileName'].split("-")[0].split(".")[0]
        srcmapdoc['URI'] = src_package

    if 'UsedBy' not in srcmapdoc:
        srcmapdoc['UsedBy'] = []

    if pkgname not in srcmapdoc['UsedBy']:
        srcmapdoc['UsedBy'].append(pkgname)

    with codecs.open(fname, mode='w', encoding='utf-8') as f:
        f.write(json.dumps(srcmapdoc, indent=4))

    return fname

do_srcmap_deploy() {
    echo "Deploying srcmap for ${PF}"
}

addtask do_srcmap_unpack after do_unpack before do_patch
addtask do_srcmap_patch after do_patch before do_configure
addtask do_srcmap_unpack before do_srcmap_patch
addtask do_srcmap_deploy before do_build after do_srcmap_patch
do_srcmap_patch[deptask] = "do_srcmap_unpack"

addtask srcmapall after do_srcmap_deploy
do_srcmapall[recrdeptask] = "do_srcmap_deploy"
do_srcmapall[recideptask] = "do_${BB_DEFAULT_TASK}"
#do_srcmapall[nostamp] = "1"
do_srcmapall() {
        :
}
