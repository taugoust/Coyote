######################################################################################
# Application-link partition-boundary and protected-static integrity evidence.
######################################################################################

proc app_link_integrity_json_escape {value} {
    return [string map [list \\ \\\\ \" \\\" \n \\n \r \\r \t \\t] $value]
}

proc app_link_integrity_json_string {value} {
    return "\"[app_link_integrity_json_escape $value]\""
}

proc app_link_integrity_json_bool {value} {
    return [expr {$value ? "true" : "false"}]
}

proc app_link_integrity_json_string_array {values} {
    set encoded {}
    foreach value $values {
        lappend encoded [app_link_integrity_json_string $value]
    }
    return "\[[join $encoded {, }]\]"
}

proc app_link_integrity_is_true {value} {
    return [expr {[string tolower [string trim $value]] in {1 true yes on}}]
}

proc app_link_integrity_property {object property {required false}} {
    if {[catch {set value [get_property $property $object]} reason]} {
        if {$required} {
            error "Unable to read $property from $object: $reason"
        }
        return ""
    }
    if {$required && [string trim $value] eq ""} {
        error "Required property $property is empty on $object"
    }
    return $value
}

proc app_link_integrity_partition_locations {pin} {
    foreach property {HD.PARTPIN_LOCS HD.PARTPIN_LOC} {
        if {![catch {set value [get_property $property $pin]}] &&
            [string trim $value] ne ""} {
            set locations {}
            foreach location $value {
                if {[string trim $location] ne ""} {
                    lappend locations $location
                }
            }
            if {[llength $locations] > 0} {
                return [lsort -ascii -unique $locations]
            }
        }
    }
    error "Partition pin $pin has no physical HD.PARTPIN_LOCS location"
}

proc app_link_integrity_write_canonical_records {path records} {
    file mkdir [file dirname $path]
    set normalized {}
    foreach record $records {
        lappend normalized [list {*}$record]
    }
    set fd [open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    foreach record [lsort -ascii $normalized] {
        puts $fd $record
    }
    close $fd
}

proc app_link_integrity_sha256_file {path} {
    if {![file isfile $path]} {
        error "Cannot fingerprint missing file: $path"
    }
    if {[catch {set output [exec sha256sum -- $path]} reason]} {
        error "Unable to fingerprint $path: $reason"
    }
    set digest [string tolower [lindex $output 0]]
    if {![regexp {^[0-9a-f]{64}$} $digest]} {
        error "sha256sum returned a malformed digest for $path: $digest"
    }
    return $digest
}

proc app_link_integrity_density_ppm {locations sites} {
    if {![string is integer -strict $locations] || $locations < 0 ||
        ![string is integer -strict $sites] || $sites <= 0} {
        error "Partition-pin density requires non-negative locations and positive pblock sites"
    }
    return [expr {($locations * 1000000 + ($sites / 2)) / $sites}]
}

proc app_link_integrity_boundary_snapshot_from_regions {regions canonical_path} {
    if {[llength $regions] == 0} {
        error "Application link has no reconfigurable partitions"
    }

    set canonical_records [list [list format coyote-app-link-partition-pins-v1]]
    set normalized_regions {}
    set total_pins 0
    set total_locations 0
    set total_sites 0
    set all_locations {}

    set sorted_regions {}
    foreach region $regions {
        lappend sorted_regions [list [dict get $region path] $region]
    }
    foreach decorated_region [lsort -ascii -index 0 $sorted_regions] {
        set region [lindex $decorated_region 1]
        foreach required {path pblock gridRanges derivedRanges siteCount pins} {
            if {![dict exists $region $required]} {
                error "Partition-region fixture is missing $required"
            }
        }
        set path [dict get $region path]
        set pblock [dict get $region pblock]
        set grid_ranges [lsort -ascii -unique [dict get $region gridRanges]]
        set derived_ranges [lsort -ascii -unique [dict get $region derivedRanges]]
        set site_count [dict get $region siteCount]
        if {![string is integer -strict $site_count] || $site_count <= 0} {
            error "Partition $path has no physical pblock sites"
        }
        if {[llength $grid_ranges] == 0 && [llength $derived_ranges] == 0} {
            error "Partition $path has no physical pblock ranges"
        }

        set pins {}
        set pin_names {}
        set location_occupancy {}
        set physical_location_count 0
        foreach pin [dict get $region pins] {
            foreach required {name direction locations} {
                if {![dict exists $pin $required]} {
                    error "Partition pin fixture in $path is missing $required"
                }
            }
            set name [dict get $pin name]
            set direction [string toupper [dict get $pin direction]]
            set locations [lsort -ascii -unique [dict get $pin locations]]
            if {$name eq "" || $direction ni {IN OUT INOUT} ||
                [llength $locations] == 0} {
                error "Partition $path has a malformed physical pin record"
            }
            if {$name in $pin_names} {
                error "Partition $path has duplicate pin $name"
            }
            lappend pin_names $name
            foreach location $locations {
                dict incr location_occupancy $location
                lappend all_locations $location
            }
            incr physical_location_count [llength $locations]
            lappend pins [dict create \
                name $name direction $direction locations $locations]
            lappend canonical_records [list \
                pin $path $name $direction {*}$locations]
        }
        if {[llength $pins] == 0} {
            error "Partition $path has no physical partition pins"
        }
        set sorted_pins {}
        foreach pin $pins {
            lappend sorted_pins [list [dict get $pin name] $pin]
        }
        set normalized_pins {}
        foreach decorated_pin [lsort -ascii -index 0 $sorted_pins] {
            lappend normalized_pins [lindex $decorated_pin 1]
        }

        set unique_location_count [dict size $location_occupancy]
        set maximum_occupancy 0
        dict for {_ occupancy} $location_occupancy {
            if {$occupancy > $maximum_occupancy} {
                set maximum_occupancy $occupancy
            }
        }
        set logical_pin_count [llength $normalized_pins]
        set density_ppm [app_link_integrity_density_ppm \
            $physical_location_count $site_count]
        lappend canonical_records [list \
            region $path $pblock $site_count \
            [list {*}$grid_ranges] [list {*}$derived_ranges]]
        lappend normalized_regions [dict create \
            path $path \
            pblock $pblock \
            gridRanges $grid_ranges \
            derivedRanges $derived_ranges \
            siteCount $site_count \
            logicalPinCount $logical_pin_count \
            physicalLocationCount $physical_location_count \
            uniquePhysicalLocationCount $unique_location_count \
            maximumLocationOccupancy $maximum_occupancy \
            locationsPerMillionPblockSites $density_ppm \
            pins $normalized_pins]
        incr total_pins $logical_pin_count
        incr total_locations $physical_location_count
        incr total_sites $site_count
    }

    if {$total_pins <= 0 || $total_locations <= 0 || $total_sites <= 0} {
        error "Application partition-pin evidence is empty"
    }
    app_link_integrity_write_canonical_records $canonical_path $canonical_records
    return [dict create \
        canonicalSha256 [app_link_integrity_sha256_file $canonical_path] \
        canonicalRecordCount [llength $canonical_records] \
        logicalPinCount $total_pins \
        physicalLocationCount $total_locations \
        uniquePhysicalLocationCount [llength [lsort -ascii -unique $all_locations]] \
        pblockSiteCount $total_sites \
        locationsPerMillionPblockSites \
            [app_link_integrity_density_ppm $total_locations $total_sites] \
        regions $normalized_regions]
}

proc app_link_integrity_capture_boundary {partition_paths canonical_path} {
    set regions {}
    foreach path $partition_paths {
        set cells [get_cells -quiet $path]
        if {[llength $cells] != 1} {
            error "Expected exactly one application partition $path, found [llength $cells]"
        }
        set cell [lindex $cells 0]
        set tail [lindex [split $path /] end]
        set pblock_name "pblock_$tail"
        set pblocks [get_pblocks -quiet $pblock_name]
        if {[llength $pblocks] != 1} {
            error "Expected exactly one application pblock $pblock_name, found [llength $pblocks]"
        }
        set pblock [lindex $pblocks 0]
        set sites [get_sites -quiet -of_objects $pblock]
        set grid_ranges [app_link_integrity_property $pblock GRID_RANGES]
        set derived_ranges [app_link_integrity_property $pblock DERIVED_RANGES]
        set pins {}
        foreach pin [get_pins -quiet -of_objects $cell] {
            lappend pins [dict create \
                name [app_link_integrity_property $pin NAME true] \
                direction [app_link_integrity_property $pin DIRECTION true] \
                locations [app_link_integrity_partition_locations $pin]]
        }
        lappend regions [dict create \
            path $path \
            pblock $pblock_name \
            gridRanges $grid_ranges \
            derivedRanges $derived_ranges \
            siteCount [llength $sites] \
            pins $pins]
    }
    return [app_link_integrity_boundary_snapshot_from_regions \
        $regions $canonical_path]
}

proc app_link_integrity_is_partition_object {name partition_paths} {
    foreach path $partition_paths {
        if {$name eq $path || [string first "${path}/" $name] == 0} {
            return true
        }
    }
    return false
}

proc app_link_integrity_static_snapshot_from_records {
    placement_records routing_records placement_path routing_path
} {
    if {[llength $placement_records] == 0} {
        error "Protected-static placement set is empty"
    }
    if {[llength $routing_records] == 0} {
        error "Protected-static routing set is empty"
    }
    app_link_integrity_write_canonical_records $placement_path \
        [linsert $placement_records 0 [list format coyote-protected-static-placement-v1]]
    app_link_integrity_write_canonical_records $routing_path \
        [linsert $routing_records 0 [list format coyote-protected-static-routing-v1]]
    return [dict create \
        placement [dict create \
            objectCount [llength $placement_records] \
            canonicalSha256 [app_link_integrity_sha256_file $placement_path]] \
        routing [dict create \
            objectCount [llength $routing_records] \
            canonicalSha256 [app_link_integrity_sha256_file $routing_path]]]
}

proc app_link_integrity_capture_protected_static {
    partition_paths placement_path routing_path
} {
    set placement_records {}
    set fixed_cells [get_cells -quiet -hierarchical \
        -filter {IS_LOC_FIXED == 1 || IS_BEL_FIXED == 1}]
    foreach cell $fixed_cells {
        set name [app_link_integrity_property $cell NAME true]
        if {[app_link_integrity_is_partition_object $name $partition_paths]} {
            continue
        }
        set loc_fixed [app_link_integrity_is_true \
            [app_link_integrity_property $cell IS_LOC_FIXED]]
        set bel_fixed [app_link_integrity_is_true \
            [app_link_integrity_property $cell IS_BEL_FIXED]]
        if {!$loc_fixed && !$bel_fixed} {
            continue
        }
        lappend placement_records [list \
            cell $name \
            [app_link_integrity_property $cell REF_NAME] \
            [app_link_integrity_property $cell LOC] \
            [app_link_integrity_property $cell BEL] \
            $loc_fixed $bel_fixed]
    }

    set routing_records {}
    set fixed_nets [get_nets -quiet -hierarchical -filter {IS_ROUTE_FIXED == 1}]
    foreach net $fixed_nets {
        set name [app_link_integrity_property $net NAME true]
        if {[app_link_integrity_is_partition_object $name $partition_paths]} {
            continue
        }
        if {![app_link_integrity_is_true \
            [app_link_integrity_property $net IS_ROUTE_FIXED]]} {
            continue
        }
        lappend routing_records [list \
            net $name \
            [app_link_integrity_property $net ROUTE_STATUS] \
            [app_link_integrity_property $net FIXED_ROUTE]]
    }

    return [app_link_integrity_static_snapshot_from_records \
        $placement_records $routing_records $placement_path $routing_path]
}

proc app_link_integrity_compare {
    before_boundary after_boundary before_static after_static
} {
    set reasons {}
    set boundary_identical true
    foreach key {
        canonicalRecordCount logicalPinCount physicalLocationCount
        uniquePhysicalLocationCount pblockSiteCount canonicalSha256
    } {
        if {[dict get $before_boundary $key] ne [dict get $after_boundary $key]} {
            set boundary_identical false
            lappend reasons "application partition-pin $key changed"
        }
    }
    set static_identical {}
    foreach kind {placement routing} {
        dict set static_identical $kind true
        foreach key {objectCount canonicalSha256} {
            if {[dict get $before_static $kind $key] ne
                [dict get $after_static $kind $key]} {
                dict set static_identical $kind false
                lappend reasons "protected-static $kind $key changed"
            }
        }
    }
    return [dict create \
        accepted [expr {[llength $reasons] == 0}] \
        boundaryIdentical $boundary_identical \
        placementIdentical [dict get $static_identical placement] \
        routingIdentical [dict get $static_identical routing] \
        reasons $reasons]
}

proc app_link_integrity_write_partition_state {fd indent state} {
    puts $fd "${indent}{"
    puts $fd "${indent}  \"canonicalSha256\": [app_link_integrity_json_string [dict get $state canonicalSha256]],"
    puts $fd "${indent}  \"canonicalRecordCount\": [dict get $state canonicalRecordCount],"
    puts $fd "${indent}  \"logicalPinCount\": [dict get $state logicalPinCount],"
    puts $fd "${indent}  \"physicalLocationCount\": [dict get $state physicalLocationCount],"
    puts $fd "${indent}  \"uniquePhysicalLocationCount\": [dict get $state uniquePhysicalLocationCount],"
    puts $fd "${indent}  \"pblockSiteCount\": [dict get $state pblockSiteCount],"
    puts $fd "${indent}  \"locationsPerMillionPblockSites\": [dict get $state locationsPerMillionPblockSites],"
    puts $fd "${indent}  \"regions\": \["
    set regions [dict get $state regions]
    for {set region_index 0} {$region_index < [llength $regions]} {incr region_index} {
        set region [lindex $regions $region_index]
        puts $fd "${indent}    {"
        puts $fd "${indent}      \"path\": [app_link_integrity_json_string [dict get $region path]],"
        puts $fd "${indent}      \"pblock\": [app_link_integrity_json_string [dict get $region pblock]],"
        puts $fd "${indent}      \"gridRanges\": [app_link_integrity_json_string_array [dict get $region gridRanges]],"
        puts $fd "${indent}      \"derivedRanges\": [app_link_integrity_json_string_array [dict get $region derivedRanges]],"
        puts $fd "${indent}      \"logicalPinCount\": [dict get $region logicalPinCount],"
        puts $fd "${indent}      \"physicalLocationCount\": [dict get $region physicalLocationCount],"
        puts $fd "${indent}      \"uniquePhysicalLocationCount\": [dict get $region uniquePhysicalLocationCount],"
        puts $fd "${indent}      \"maximumLocationOccupancy\": [dict get $region maximumLocationOccupancy],"
        puts $fd "${indent}      \"pblockSiteCount\": [dict get $region siteCount],"
        puts $fd "${indent}      \"locationsPerMillionPblockSites\": [dict get $region locationsPerMillionPblockSites],"
        puts $fd "${indent}      \"pins\": \["
        set pins [dict get $region pins]
        for {set pin_index 0} {$pin_index < [llength $pins]} {incr pin_index} {
            set pin [lindex $pins $pin_index]
            set comma [expr {$pin_index + 1 < [llength $pins] ? "," : ""}]
            puts $fd "${indent}        {\"name\": [app_link_integrity_json_string [dict get $pin name]], \"direction\": [app_link_integrity_json_string [dict get $pin direction]], \"locations\": [app_link_integrity_json_string_array [dict get $pin locations]]}$comma"
        }
        puts $fd "${indent}      \]"
        set comma [expr {$region_index + 1 < [llength $regions] ? "," : ""}]
        puts $fd "${indent}    }$comma"
    }
    puts $fd "${indent}  \]"
    puts -nonewline $fd "${indent}}"
}

proc app_link_integrity_write_partition_manifest {
    path metadata before_boundary after_boundary comparison
} {
    file mkdir [file dirname $path]
    set fd [open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "{"
    puts $fd {  "schemaVersion": 1,}
    puts $fd {  "api": "coyote.app-link-partition-pins/v1",}
    puts $fd {  "kind": "coyote-application-partition-pin-manifest",}
    puts $fd "  \"board\": [app_link_integrity_json_string [dict get $metadata board]],"
    puts $fd "  \"fpgaArchitecture\": [app_link_integrity_json_string [dict get $metadata architecture]],"
    puts $fd "  \"fpgaPart\": [app_link_integrity_json_string [dict get $metadata part]],"
    puts $fd "  \"configuration\": [dict get $metadata configuration],"
    puts $fd "  \"identical\": [app_link_integrity_json_bool [dict get $comparison boundaryIdentical]],"
    puts $fd {  "densityUnit": "physical-partition-pin-locations-per-million-pblock-sites",}
    puts $fd {  "lockedShell": }
    app_link_integrity_write_partition_state $fd "  " $before_boundary
    puts $fd ","
    puts $fd {  "linkedApplication": }
    app_link_integrity_write_partition_state $fd "  " $after_boundary
    puts $fd ""
    puts $fd "}"
    close $fd
}

proc app_link_integrity_write_static_pair {fd indent before after identical} {
    puts $fd "${indent}{"
    puts $fd "${indent}  \"before\": {\"objectCount\": [dict get $before objectCount], \"sha256\": [app_link_integrity_json_string [dict get $before canonicalSha256]]},"
    puts $fd "${indent}  \"after\": {\"objectCount\": [dict get $after objectCount], \"sha256\": [app_link_integrity_json_string [dict get $after canonicalSha256]]},"
    puts $fd "${indent}  \"identical\": [app_link_integrity_json_bool $identical]"
    puts -nonewline $fd "${indent}}"
}

proc app_link_integrity_write_summary {
    path partition_manifest_name metadata before_boundary after_boundary
    before_static after_static comparison
} {
    set boundary_identical [expr {
        [dict get $before_boundary canonicalSha256] eq
        [dict get $after_boundary canonicalSha256]
    }]
    set placement_identical [expr {
        [dict get $before_static placement canonicalSha256] eq
        [dict get $after_static placement canonicalSha256] &&
        [dict get $before_static placement objectCount] ==
        [dict get $after_static placement objectCount]
    }]
    set routing_identical [expr {
        [dict get $before_static routing canonicalSha256] eq
        [dict get $after_static routing canonicalSha256] &&
        [dict get $before_static routing objectCount] ==
        [dict get $after_static routing objectCount]
    }]
    set outcome [expr {[dict get $comparison accepted] ? "accepted" : "rejected"}]

    file mkdir [file dirname $path]
    set fd [open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "{"
    puts $fd {  "schemaVersion": 1,}
    puts $fd {  "api": "coyote.app-link-integrity/v1",}
    puts $fd {  "kind": "coyote-application-link-integrity",}
    puts $fd "  \"outcome\": [app_link_integrity_json_string $outcome],"
    puts $fd "  \"board\": [app_link_integrity_json_string [dict get $metadata board]],"
    puts $fd "  \"fpgaArchitecture\": [app_link_integrity_json_string [dict get $metadata architecture]],"
    puts $fd "  \"fpgaPart\": [app_link_integrity_json_string [dict get $metadata part]],"
    puts $fd "  \"configuration\": [dict get $metadata configuration],"
    puts $fd "  \"vivadoVersion\": [app_link_integrity_json_string [dict get $metadata vivadoVersion]],"
    puts $fd "  \"shell\": {"
    puts $fd "    \"exportCmakeSha256\": [app_link_integrity_json_string [dict get $metadata shellContractSha256]],"
    puts $fd "    \"routedLockedCheckpointSha256\": [app_link_integrity_json_string [dict get $metadata shellCheckpointSha256]]"
    puts $fd "  },"
    puts $fd "  \"partitionPins\": {"
    puts $fd "    \"manifest\": [app_link_integrity_json_string $partition_manifest_name],"
    puts $fd "    \"beforeSha256\": [app_link_integrity_json_string [dict get $before_boundary canonicalSha256]],"
    puts $fd "    \"afterSha256\": [app_link_integrity_json_string [dict get $after_boundary canonicalSha256]],"
    puts $fd "    \"logicalPinCount\": [dict get $after_boundary logicalPinCount],"
    puts $fd "    \"physicalLocationCount\": [dict get $after_boundary physicalLocationCount],"
    puts $fd "    \"pblockSiteCount\": [dict get $after_boundary pblockSiteCount],"
    puts $fd "    \"locationsPerMillionPblockSites\": [dict get $after_boundary locationsPerMillionPblockSites],"
    puts $fd "    \"identical\": [app_link_integrity_json_bool $boundary_identical]"
    puts $fd "  },"
    puts $fd "  \"protectedStatic\": {"
    puts $fd {    "selection": "objects outside every application RP with IS_LOC_FIXED, IS_BEL_FIXED, or IS_ROUTE_FIXED",}
    puts $fd {    "placement": }
    app_link_integrity_write_static_pair $fd "    " \
        [dict get $before_static placement] [dict get $after_static placement] \
        $placement_identical
    puts $fd ","
    puts $fd {    "routing": }
    app_link_integrity_write_static_pair $fd "    " \
        [dict get $before_static routing] [dict get $after_static routing] \
        $routing_identical
    puts $fd ""
    puts $fd "  },"
    puts $fd "  \"reasons\": [app_link_integrity_json_string_array [dict get $comparison reasons]]"
    puts $fd "}"
    close $fd
}

proc app_link_integrity_validate_and_write {
    partition_manifest_path summary_path metadata before_boundary after_boundary
    before_static after_static
} {
    set comparison [app_link_integrity_compare \
        $before_boundary $after_boundary $before_static $after_static]
    app_link_integrity_write_partition_manifest \
        $partition_manifest_path $metadata $before_boundary $after_boundary $comparison
    app_link_integrity_write_summary \
        $summary_path [file tail $partition_manifest_path] $metadata \
        $before_boundary $after_boundary $before_static $after_static $comparison
    if {![dict get $comparison accepted]} {
        error "Application link integrity check failed: [join [dict get $comparison reasons] {; }]"
    }
    return $comparison
}
