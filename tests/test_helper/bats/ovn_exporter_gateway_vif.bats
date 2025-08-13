# This is a bash shell fragment -*- bash -*-

load "${ABS_TOP_TEST_DIRNAME}test_helper/setup_teardown_exporter/$(basename "${BATS_TEST_FILENAME//.bats/.bash}")"

setup() {
    load ${ABS_TOP_TEST_DIRNAME}test_helper/common.bash
    load ${ABS_TOP_TEST_DIRNAME}test_helper/lxd.bash
    load ${ABS_TOP_TEST_DIRNAME}test_helper/microovn.bash
    load ${ABS_TOP_TEST_DIRNAME}../.bats/bats-support/load.bash
    load ${ABS_TOP_TEST_DIRNAME}../.bats/bats-assert/load.bash

    # Ensure TEST_CONTAINERS is populated, otherwise the tests below will
    # provide false positive results.
    assert [ -n "$TEST_CONTAINERS" ]
}

teardown() {
    # Clean up any exporter processes
    for container in $TEST_CONTAINERS; do
        lxc_exec "$container" "pkill -f ovn-exporter" || true
    done
}

@test "Testing OVN exporter with gateway and VIF setup" {
    ovn_exporter_gateway_vif_test
}

ovn_exporter_gateway_vif_test() {
    # Test on chassis containers where we set up the gateway and VIF
    for container in $CHASSIS_CONTAINERS; do
        # Verify that the network objects created in setup_file exist
        # The microovn helper functions create objects with specific naming patterns
        local expected_ls_name="sw-${container}"
        local expected_lr_name="lr-${container}"
        
        run lxc_exec "$container" "microovn.ovn-nbctl ls-list"
        assert_success
        assert_output --partial "$expected_ls_name"
        
        run lxc_exec "$container" "microovn.ovn-nbctl lr-list"
        assert_success
        assert_output --partial "$expected_lr_name"
        
        echo "# $container: Network topology verified (from setup_file)"
        
        # Start ovn-exporter in background with MicroOVN environment
        lxc_exec "$container" "
            export OVS_RUNDIR='/var/snap/microovn/common/run/switch'
            export OVN_RUNDIR='/var/snap/microovn/common/run/ovn'
            export OVS_VSWITCHD_PID='/var/snap/microovn/common/run/switch/ovs-vswitchd.pid'
            export OVSDB_SERVER_PID='/var/snap/microovn/common/run/switch/ovsdb-server.pid'
            export OVN_NBDB_LOCATION='/var/snap/microovn/common/data/central/db/ovnnb_db.db'
            export OVN_SBDB_LOCATION='/var/snap/microovn/common/data/central/db/ovnsb_db.db'
            /tmp/ovn-exporter --loglevel info --host 0.0.0.0 --port 9310
        " &
        
        # Give exporter time to start and collect metrics
        sleep 7
        
        # Verify exporter is running
        run lxc_exec "$container" "pgrep -f ovn-exporter"
        assert_success
        echo "# $container: Exporter process is running"
        
        # Test that metrics endpoint returns data
        run lxc_exec "$container" "curl -s http://localhost:9310/metrics"
        assert_success
        assert_output --partial "# HELP"
        assert_output --partial "# TYPE"
        
        # Test that OVS metrics are present with our gateway/VIF network setup
        run lxc_exec "$container" "curl -s http://localhost:9310/metrics"
        assert_success
        
        # Check for core OVS metrics
        assert_output --partial "ovs_build_info"
        assert_output --partial "ovs_vswitchd_bridge"
        assert_output --partial "ovs_vswitchd_process_"
        assert_output --partial "ovs_db_process_"
        
        echo "# $container: OVS metrics verification passed"
        
        # Test that the exporter handles the gateway/VIF network topology properly
        # by verifying it doesn't crash and continues serving metrics
        sleep 3
        
        run lxc_exec "$container" "curl -s http://localhost:9310/metrics | wc -l"
        assert_success
        # Should have a reasonable number of metrics lines (at least 50)
        local metrics_count
        metrics_count=$(echo "$output" | tr -d ' ')
        assert [ "$metrics_count" -gt 50 ]
        
        echo "# $container: Extended metrics verification passed with gateway/VIF topology"
        
        # Verify network objects are still present (ensuring exporter didn't interfere)
        run lxc_exec "$container" "microovn.ovn-nbctl ls-list | grep -c '$expected_ls_name'"
        assert_success
        assert [ "$output" -eq 1 ]  # Should have exactly one switch with our name
        
        run lxc_exec "$container" "microovn.ovn-nbctl lr-list | grep -c '$expected_lr_name'"
        assert_success  
        assert [ "$output" -eq 1 ]  # Should have exactly one router with our name
        
        echo "# $container: Network topology integrity verified"
        
        # Test ping connectivity in the VIF namespace (following upgrade.bash pattern)
        local ctn_n
        ctn_n=$(microovn_extract_ctn_n "$container")
        run lxc_exec "$container" "ip netns exec $GATEWAY_VIF_NS_NAME ping -c 3 10.42.${ctn_n}.1"
        assert_success
        echo "# $container: VIF ping connectivity verified (3 packets sent successfully)"
        
        # Check current ping packet loss from background ping
        local n_lost
        n_lost=$(ping_packets_lost "$container" 10.42.${ctn_n}.1 "$GATEWAY_VIF_NS_NAME") || true
        echo "# $container: Background ping packets lost so far: ${n_lost:-0}"
        
        # Clean up processes for next iteration
        lxc_exec "$container" "pkill -f ovn-exporter" || true
        sleep 1
    done
}