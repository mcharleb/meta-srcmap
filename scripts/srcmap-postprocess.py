#!/opt/pypy/bin/pypy

def scan_pkgfiles(files, dname, fname, pkgdoc, filecount):
    import hashlib

    if fname not in pkgdoc['package_files']:
        pkgdoc['package_files'][fname] = {}

    if dname not in pkgdoc['package_files'][fname]:
        pkgdoc['package_files'][fname][dname] = {}


    for f in files:
        if not os.path.islink(os.path.join(dname, f)):
            with open(os.path.join(dname, f), 'rb') as curfile:
                pkgdoc['package_files'][fname][dname][f] = hashlib.md5(curfile.read()).hexdigest()
                print(os.path.join(dname, f))
                filecount += 1
    return filecount

def scan_extracted(fname, extracteddir, pkgdoc):
    import time

    if fname not in pkgdoc['package_files']:
        pkgdoc['package_files'][fname] = {}

    if 1:
        t0 = time.time()
        filecount = 0
        for dname, subdirs, files in os.walk(extracteddir):
            for f in files:
                filecount = scan_pkgfiles(files, dname, fname, pkgdoc, filecount)
                t1 = time.time()
                total = t1-t0
                print("Scanned %d files in %d" % (filecount, total))

def filehash(fname):
    import hashlib

    with open(fname, 'rb') as curfile:
        return hashlib.md5(curfile.read()).hexdigest()

    print("ERROR: cound not open %s" % fname)
    raise SystemExit

def scan(node, extracteddir, pkgname):
    import hashlib

    pkgbname = os.path.basename(pkgname)
    pname = os.path.join(scandir, pkgbname+".scan")
    pkgdoc = {}
    pkgdoc['packages'] = {}
    pkgdoc['files'] = {}
    pkgdoc['package_files'] = {}
    if os.path.isfile(pname):
        print("LOADING: %s" % pname)
        with codecs.open(pname, mode='r', encoding='utf-8') as f:
            pkgdoc = json.load(f)

    if os.path.isfile(node):
        if os.path.islink(node):
            return

        found = 0
        dname = os.path.dirname(node)
        bname = os.path.basename(node)

        if node.endswith(".tar.gz") or node.endswith(".tar.bz2") or node.endswith(".tar.xz"):
            if dname in pkgdoc['packages']:
                if bname in pkgdoc['packages'][dname]:
                    found = 1
            else:
                pkgdoc['packages'][dname] = {}

            newhash = filehash(node)
            if not found:
                pkgdoc['packages'][dname][bname] = newhash
                scan_extracted(node, extracteddir, pkgdoc)
            else:
                if newhash != pkgdoc['packages'][dname][bname]:
                    pkgdoc['packages'][dname][bname] = newhash
                    scan_extracted(node, extracteddir, pkgdoc)
        else:
            if dname in pkgdoc['files']:
                if bname in pkgdoc['files'][dname]:
                    found = 1
            else:
                pkgdoc['files'][dname] = {}

            if not found:
                pkgdoc['files'][dname][bname] = filehash(node)

    elif os.path.isdir(node):
        # This should not happen
        print("ERROR: Directory passed as file to scan")
        raise SystemExit
    else:
        print("ERROR: path not found: %s" % node)
        raise SystemExit

    with codecs.open(pname, mode='w', encoding='utf-8') as f:
            f.write(json.dumps(pkgdoc, indent = 4))
    
    
def get_license_from_smpkg(pkgname):
    if not pkgname:
        print("ERROR: packagename is empty")
        raise SystemExit

    if pkgname in [ 'HOST-PACKAGE', 'SKIPPED-NATIVE' ]:
        return "UNKNOWN"
        
    with codecs.open(pkgname, mode='r', encoding='utf-8') as f:
        smpkgdoc = json.load(f)
        if 'LICENSE' in smpkgdoc:
            return smpkgdoc['LICENSE']
    return "UNKNOWN"

def get_src_provider_file(dname):
    if dname in src_provider_map:
        return src_provider_map[dname]
    return "UNKNOWN"

def dump_smpkg(pkgname, dumped_list):
    import glob
    import codecs
    import json
    import os

    deps = {}
    if os.path.isfile(pkgname) and pkgname not in dumped_list:
        print("")
        print("TARGET: "+pkgname);
        with codecs.open(pkgname, mode='r', encoding='utf-8') as f:
            smpkgdoc = json.load(f)
            #print(json.dumps(smpkgdoc, indent = 4))

            if 'DEPENDS' in smpkgdoc:
                for pkg in smpkgdoc['DEPENDS']:
                    fname = get_dependency_file(pkg)
                    deps[pkg] = fname

            if 'ImagePackages' in smpkgdoc:
                for pkg in smpkgdoc['ImagePackages'].split():
                    fname = get_dependency_file(pkg)
                    deps[pkg] = fname

            srcdirdep = ""
            if 'UnresolvedSrcDir' in smpkgdoc:
                srcdirdep = get_src_provider_file(smpkgdoc['UnresolvedSrcDir'])

            print("    DeclaredLicense:")
            print("        %s" % smpkgdoc["LICENSE"])

            print("    Provides:")
            for f in smpkgdoc["PROVIDES"]:
                print("        %s" % f)

            print("    Dependencies:")
            for f in deps:
                if deps[f] not in [ 'HOST-PACKAGE', 'SKIPPED-NATIVE' ]:
                    if not deps[f]:
                        print("WARNING: Missing dependency file for %s" % f)
                        continue
                    print("        %s -> %s (%s)" % (f, deps[f], get_license_from_smpkg(deps[f])))

            if 'DownloadURIs' in smpkgdoc:
                for f in smpkgdoc['DownloadURIs']:
                    print("        %s -> %s" % (f[0], f[1]))

            if srcdirdep:
                    print("        %s -> %s" % (smpkgdoc['UnresolvedSrcDir'], srcdirdep))

            print("    PackageFiles:")
            if 'PatchedFiles' in smpkgdoc:
                for p in smpkgdoc['PatchedFiles']:
                    fname = os.path.join(smpkgdoc['SourceDir'], p)
                    print("        %s" % fname)
                    #scan(fname, "", pkgname)
            if 'Files' in smpkgdoc:
                for p in smpkgdoc['Files']:
                    fname = p[1]
                    print("        %s" % fname)
                    #scan(fname, "", pkgname)

            dumped_list.append(pkgname)

            for f in deps:
                dump_smpkg(deps[f], dumped_list)
                
            if 'DownloadURIs' in smpkgdoc:
                for s in smpkgdoc['DownloadURIs']:
                    fname = s[1]
                    if os.path.isfile(fname) and fname not in dumped_list:
                        dump_uri_info(fname)
                        dumped_list.append(fname)
            if srcdirdep:
                dump_smpkg(srcdirdep, dumped_list)


# Display the info for the dependent URI
def dump_uri_info(fname):
    print(" ")
    print("DOWNLOAD: "+fname);
    with codecs.open(fname, mode='r', encoding='utf-8') as f2:
        uridoc = json.load(f2)
        print("    URI:")
        print("        %s" % uridoc['URI'])
        print("    Source:")
        print("        %s" % uridoc['Source'])
        #scan(uridoc['Source'], uridoc['ExtractedDir'], fname)

def get_dependency_file(pkg):
    if pkg in host_pkgs:
        return "HOST-PACKAGE"

    filename = ""

    # opencv generates package names at build time
    if pkg.startswith("libopencv-"):
        pkg = "opencv"

    # virtual/kernel generates package names at build time
    if pkg.startswith("kernel-module-"):
        pkg = "virtual/kernel"

    if pkg in provider_map:
        filename = provider_map[pkg]
    elif pkg in package_map:
        filename = package_map[pkg]
    else:
        if pkg.endswith("-native"):
            basepkg = pkg.split("-native")[0]
            if basepkg in provider_map:
                filename = provider_map[basepkg]
            elif basepkg in package_map:
                filename = package_map[basepkg]

    if skip_native:
        for x in [ "-cross-", "-native-", "-initial-" ]:
            if x in filename:
                skip = 1
                filename = "SKIPPED-NATIVE"

    if not filename:
            print("ERROR: COULD NOT FIND DEPENDENCY FILE FOR %s" % pkg)
    
    return filename

def package_whitelist_check(p, pkgmap, deppkgfile):
    MULTI_PROVIDER_WHITELIST="virtual/libintl virtual/libintl-native virtual/nativesdk-libintl virtual/xserver virtual/update-alternatives-native virtual/update-alternatives".split()

    if p in pkgmap and pkgmap[p] != deppkgfile:
        if not p in MULTI_PROVIDER_WHITELIST:
            print("ERROR: duplicate providers for package %s:" % p) 
            print("    PROVIDER 1: %s" % pkgmap[p]) 
            print("    PROVIDER 2: %s" % deppkgfile) 
        else:
            print("INFO: %s is multi-provider whitelisted" % p)

    # FIXME - find correct override
    return deppkgfile


def usage():
    print("%s [--help] [--skip-native] [-I pkgname] target" % os.path.basename(os.sys.argv[0]))

if __name__ == "__main__":
    import os
    import json
    import glob
    import codecs
    dumped_list = []

    if "--help" in os.sys.argv:
        usage()
        raise SystemExit

    skip_native = 0 
    if "--skip-native" in os.sys.argv:
        skip_native = 1

    args = [ x for x in os.sys.argv if x not in [ "--help", "--skip-native", "-I" ] ]

    if len(args) < 1:
        usage()
        raise SystemExit

    ASSUME_PROVIDED="bzip2-native chrpath-native file-native findutils-native git-native grep-native diffstat-native patch-native libgcc-native hostperl-runtime-native hostpython-runtime-native tar-native virtual/libintl-native virtual/libiconv-native texinfo-native bash-native sed-native wget-native "

    host_pkgs = args[:-1] + ASSUME_PROVIDED.split()
    rootpkg = args[-1]
    builddir = os.environ['BUILDDIR']
    spkgdir = os.path.join(builddir,"srcmap-output")
    scandir = os.path.join(builddir,"scan-output")

    if not os.path.exists(scandir):
        os.makedirs(scandir)

    # Index the files by provider
    src_provider_map = {}
    provider_map = {}
    package_map = {}
    for deppkgfile in glob.glob(os.path.join(spkgdir, "*.smpkg")):
        with codecs.open(deppkgfile, mode='r', encoding='utf-8') as f:
            smpkgdoc = json.load(f)
            if 'PROVIDES' in smpkgdoc:
               for p in smpkgdoc['PROVIDES']:
                   provider_map[p] = package_whitelist_check(p, provider_map, deppkgfile)
            if 'PACKAGES' in smpkgdoc:
               for p in smpkgdoc['PACKAGES']:
                   package_map[p] = package_whitelist_check(p, package_map, deppkgfile)
            if 'ProvidesSource' in smpkgdoc:
                   p = smpkgdoc['ProvidesSource']
                   if p in src_provider_map:
                       print("ERROR: duplicate src providers for src dir %s:" % p) 
                       print("    PROVIDER 1: %s" % src_provider_map[p]) 
                       print("    PROVIDER 2: %s" % deppkgfile) 
                   src_provider_map[p] = deppkgfile

    #print(json.dumps(provider_map, indent = 4))
    #print(json.dumps(package_map, indent = 4))
    #print(json.dumps(src_provider_map, indent = 4))

    if rootpkg in provider_map:
        dump_smpkg(provider_map[rootpkg], dumped_list)
    elif rootpkg in package_map:
        dump_smpkg(package_map[rootpkg], dumped_list)

