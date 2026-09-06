if {$argc != 5} {
    puts stderr "usage: template_contract.tcl APP_LINK_INTEGRITY.tcl FLOW_APP_LINK.tcl FindCoyoteHW.cmake U280_FIXTURE.tcl V80_FIXTURE.tcl"
    exit 2
}

lassign $argv helper_path flow_path cmake_path u280_fixture_path v80_fixture_path

proc read_source {path} {
    set fd [open $path r]
    set source [read $fd]
    close $fd
    if {![info complete $source]} {
        error "incomplete Tcl source: $path"
    }
    return $source
}

proc require_true {condition label} {
    if {!$condition} {
        error "$label"
    }
}

proc require_equal {actual expected label} {
    if {$actual ne $expected} {
        error "$label: expected '$expected', got '$actual'"
    }
}

proc require_text {source needle label} {
    if {[string first $needle $source] < 0} {
        error "$label is missing '$needle'"
    }
}

proc require_order {source needles label} {
    set previous -1
    foreach needle $needles {
        set current [string first $needle $source]
        if {$current < 0 || $current <= $previous} {
            error "$label does not preserve required order at '$needle'"
        }
        set previous $current
    }
}

proc load_fixture {path} {
    source $path
    return [dict create \
        name $fixture_name \
        architecture $fixture_architecture \
        part $fixture_part \
        expectedDensity $fixture_expected_density \
        boundaryRegions $fixture_boundary_regions \
        placementRecords $fixture_placement_records \
        routingRecords $fixture_routing_records]
}

proc reverse_boundary_fixture {regions} {
    set reversed {}
    foreach region [lreverse $regions] {
        dict set region pins [lreverse [dict get $region pins]]
        dict set region gridRanges [lreverse [dict get $region gridRanges]]
        dict set region derivedRanges [lreverse [dict get $region derivedRanges]]
        lappend reversed $region
    }
    return $reversed
}

proc mutate_boundary_location {regions} {
    set region [lindex $regions 0]
    set pins [dict get $region pins]
    set pin [lindex $pins 0]
    dict set pin locations [list INT_X999Y999/DRIFT]
    lset pins 0 $pin
    dict set region pins $pins
    lset regions 0 $region
    return $regions
}

proc mutate_placement {records} {
    set record [lindex $records 0]
    lset record 3 SLICE_X999Y999
    lset records 0 $record
    return $records
}

proc mutate_routing {records} {
    set record [lindex $records 0]
    lset record 3 {INT_X999Y999/DRIFT}
    lset records 0 $record
    return $records
}

proc require_json {path expression label} {
    if {[catch {exec jq -e $expression $path} output]} {
        error "$label: $output"
    }
}

set helper [read_source $helper_path]
source $helper_path
set flow [read_source $flow_path]
set cmake [read_source $cmake_path]

foreach required {
    app_link_integrity_capture_boundary
    HD.PARTPIN_LOCS
    IS_LOC_FIXED
    IS_BEL_FIXED
    IS_ROUTE_FIXED
    FIXED_ROUTE
    locationsPerMillionPblockSites
    coyote.app-link-partition-pins/v1
    coyote.app-link-integrity/v1
} {
    require_text $helper $required "application-link integrity helper"
}
require_order $flow [list \
    {set before_boundary [app_link_integrity_capture_boundary} \
    {link_design -mode default} \
    {set after_boundary [app_link_integrity_capture_boundary} \
    {app_link_integrity_validate_and_write} \
    {write_checkpoint -force}] \
    "application-link integrity gate"
foreach forbidden {opt_design place_design phys_opt_design route_design write_bitstream} {
    if {[string first $forbidden $flow] >= 0} {
        error "link-only template contains forbidden implementation command: $forbidden"
    }
}
foreach required {
    {scripts/dyn/app_link_integrity.tcl}
    {reports/config_${i}/app_link_partition_pins_c${i}.json}
    {reports/config_${i}/app_link_integrity_c${i}.json}
    {BYPRODUCTS ${DEP_DCP_LIST_APP_LINK} ${DEP_APP_LINK_EVIDENCE}}
    {${CMAKE_BINARY_DIR}/app_link_integrity.tcl}
} {
    require_text $cmake $required "CMake application-link artifact contract"
}

set output_root [file normalize [file join [pwd] "app-link-integrity-contract-[pid]"]]
file delete -force $output_root
file mkdir $output_root

foreach fixture_path [list $u280_fixture_path $v80_fixture_path] {
    set fixture [load_fixture $fixture_path]
    set name [dict get $fixture name]
    set case_dir [file join $output_root $name]
    file mkdir $case_dir

    set before_boundary [app_link_integrity_boundary_snapshot_from_regions \
        [dict get $fixture boundaryRegions] \
        [file join $case_dir before-boundary.txt]]
    set after_boundary [app_link_integrity_boundary_snapshot_from_regions \
        [reverse_boundary_fixture [dict get $fixture boundaryRegions]] \
        [file join $case_dir after-boundary.txt]]
    require_equal [dict get $before_boundary canonicalSha256] \
        [dict get $after_boundary canonicalSha256] \
        "$name partition-pin canonical ordering"
    require_equal [dict get $after_boundary locationsPerMillionPblockSites] \
        [dict get $fixture expectedDensity] \
        "$name partition-pin density"

    set before_static [app_link_integrity_static_snapshot_from_records \
        [dict get $fixture placementRecords] \
        [dict get $fixture routingRecords] \
        [file join $case_dir before-placement.txt] \
        [file join $case_dir before-routing.txt]]
    set after_static [app_link_integrity_static_snapshot_from_records \
        [lreverse [dict get $fixture placementRecords]] \
        [lreverse [dict get $fixture routingRecords]] \
        [file join $case_dir after-placement.txt] \
        [file join $case_dir after-routing.txt]]

    # Different application sizes/distances are intentionally absent from the
    # physical ABI snapshots. If they consume one shell contract and preserve
    # its boundary/static state, the generic gate accepts both variants.
    set accepted [app_link_integrity_compare \
        $before_boundary $after_boundary $before_static $after_static]
    require_true [dict get $accepted accepted] \
        "$name ABI-identical application variants were rejected"
    require_true [app_link_integrity_is_partition_object \
        inst_shell/inst_dynamic/inst_user_wrapper_0/variant_internal_reg \
        [list inst_shell/inst_dynamic/inst_user_wrapper_0]] \
        "$name application internals are not excluded from protected static"

    set metadata [dict create \
        board $name \
        architecture [dict get $fixture architecture] \
        part [dict get $fixture part] \
        configuration 0 \
        vivadoVersion fixture \
        shellContractSha256 [string repeat a 64] \
        shellCheckpointSha256 [string repeat b 64]]
    set partition_json [file join $case_dir app_link_partition_pins_c0.json]
    set summary_json [file join $case_dir app_link_integrity_c0.json]
    app_link_integrity_validate_and_write \
        $partition_json $summary_json $metadata \
        $before_boundary $after_boundary $before_static $after_static
    require_json $partition_json \
        {.schemaVersion == 1 and .identical == true and .lockedShell.logicalPinCount > 0 and .lockedShell.locationsPerMillionPblockSites > 0 and (.linkedApplication.regions[0].pins | length) > 0} \
        "$name partition-pin JSON"
    require_json $summary_json \
        {.outcome == "accepted" and .partitionPins.identical == true and .protectedStatic.placement.identical == true and .protectedStatic.routing.identical == true and (.reasons | length) == 0} \
        "$name accepted integrity JSON"

    set drift_boundary [app_link_integrity_boundary_snapshot_from_regions \
        [mutate_boundary_location [dict get $fixture boundaryRegions]] \
        [file join $case_dir drift-boundary.txt]]
    set rejected_partition_json [file join $case_dir rejected-partition.json]
    set rejected_summary_json [file join $case_dir rejected-boundary.json]
    if {![catch {
        app_link_integrity_validate_and_write \
            $rejected_partition_json $rejected_summary_json $metadata \
            $before_boundary $drift_boundary $before_static $after_static
    } reason] || [string first "partition-pin" $reason] < 0} {
        error "$name boundary drift did not fail closed: $reason"
    }
    require_json $rejected_summary_json \
        {.outcome == "rejected" and .partitionPins.identical == false and (.reasons | any(contains("partition-pin")))} \
        "$name boundary-drift rejection JSON"

    set drift_placement [app_link_integrity_static_snapshot_from_records \
        [mutate_placement [dict get $fixture placementRecords]] \
        [dict get $fixture routingRecords] \
        [file join $case_dir drift-placement.txt] \
        [file join $case_dir stable-routing.txt]]
    set placement_comparison [app_link_integrity_compare \
        $before_boundary $after_boundary $before_static $drift_placement]
    require_true [expr {![dict get $placement_comparison accepted]}] \
        "$name protected-static placement drift was accepted"
    require_true [expr {![dict get $placement_comparison placementIdentical]}] \
        "$name placement fingerprint did not change"

    set drift_routing [app_link_integrity_static_snapshot_from_records \
        [dict get $fixture placementRecords] \
        [mutate_routing [dict get $fixture routingRecords]] \
        [file join $case_dir stable-placement.txt] \
        [file join $case_dir drift-routing.txt]]
    set routing_comparison [app_link_integrity_compare \
        $before_boundary $after_boundary $before_static $drift_routing]
    require_true [expr {![dict get $routing_comparison accepted]}] \
        "$name protected-static route drift was accepted"
    require_true [expr {![dict get $routing_comparison routingIdentical]}] \
        "$name route fingerprint did not change"
}

file delete -force $output_root
puts "APP_LINK_INTEGRITY_TEMPLATE_PASS boards=u280,v80"
