module StdlibRegistryCompatUpdater

using RegistryTools
using Pkg
using Pkg: Registry, Versions
using UUIDs

const JULIA_UUID = UUID("1222c4b2-2114-5bfd-aeef-88e4692bbb3e")

const ANY_VERSION = Pkg.Versions.VersionSpec("*")

function versionrange(lo::Versions.VersionBound, hi::Versions.VersionBound)
    lo.t == hi.t && (lo = hi)
    return Versions.VersionRange(lo, hi)
end

function convert_to_registrator_format(compat_dict::Dict, reg)
    new_compat = Dict{VersionNumber, Dict{Any, Any}}()
    for (v, compat_info) in compat_dict
        d = Dict()
        for (uuid, spec) in compat_info
            if spec != ANY_VERSION
                pkg_name = if haskey(Pkg.Types.stdlibs(), uuid)
                    first(Pkg.Types.stdlibs()[uuid])
                else
                    reg[uuid].name
                end

                # Taken from https://github.com/JuliaRegistries/RegistryTools.jl/blob/841a56d8274e2857e3fd5ea993ba698cdbf51849/src/register.jl#L532
                ranges = map(r->versionrange(r.lower, r.upper), spec.ranges)
                ranges = Versions.VersionSpec(ranges).ranges # this combines joinable ranges
                d[pkg_name] = length(ranges) == 1 ? string(ranges[1]) : map(string, ranges)
            end
        end
        new_compat[v] = d
    end
    return new_compat
end

function update_compat_for_stdlib((stdlib_uuid, stdlib_name)::Pair{UUID, String})
    # Dict{Name, VersionRange}
    # Check that it is a git version
    reg = Pkg.Registry.reachable_registries()[1]
    if !isdir(joinpath(reg.path, ".git"))
        error("needs a git registry")
    end
    depends_on_stdlib = false
    for (uuid, entry) in reg
        entry.name == "julia" && continue
        info = Registry.registry_info(entry)
        for (vr, deps) in info.deps
            for (name, uuid) in deps
                if name == stdlib_name
                    depends_on_stdlib = true
                    @goto done
                end
            end
        end
        @label done
        if depends_on_stdlib
            compat_info = Registry.compat_info(info)
            for (version, compat) in compat_info
                # Check if this version depends on DelimitedFiles
                if haskey(compat, stdlib_uuid)
                    # @info "Version $version of pkg $(entry.name) depends on DelimitedFiles"

                    v = get(compat, JULIA_UUID, ANY_VERSION)
                    if compat[stdlib_uuid] == ANY_VERSION
                        # Not really supposed to mutate this.....
                        compat[stdlib_uuid] = v
                    end
                end
            end

            # Write out the new compat
            reg_dict = convert_to_registrator_format(compat_info, reg)
            RegistryTools.Compress.save(joinpath(reg.path, entry.path, "Compat.toml"), reg_dict)
        end
    end

end

# StdlibRegistryCompatUpdater.register("LazyArtifacts", "/home/vchuravy/src/LazyArtifacts", "https://github.com/JuliaPackaging/LazyArtifacts.jl")

function register(stdlib_name::String, package_path::String, package_repo::String="https://github.com/JuliaLang/$(stdlib_name).jl")
    reg = Pkg.Registry.reachable_registries()[1]
    if !isdir(joinpath(reg.path, ".git"))
        error("needs a git registry")
    end
    if !endswith(package_repo, ".git")
        package_repo *= ".git"
    end
    tree_hash = bytes2hex(Pkg.GitTools.tree_hash(package_path))
    project_path = joinpath(package_path, "Project.toml")
    @info "Registering..." package_repo project_path tree_hash
    RegistryTools.register(package_repo, project_path, tree_hash)
end

end # module StdlibRegistryCompatUpdater
