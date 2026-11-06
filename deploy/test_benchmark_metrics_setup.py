import copy
import unittest
from unittest.mock import patch

import benchmark_host as host
import benchmark_metrics as metrics
import benchmark_metrics_setup as setup
import test_benchmark_host as fixture
import test_benchmark_rollout as rollout_fixture


class SetupHost(setup.Setup, rollout_fixture.RolloutHost):
    def __init__(self, root):
        super().__init__(root)
        self.extension = False
        self.schema = False
        self.fail_database = False
        self.fail_extension = False

    def docker(self,*args,**kwargs):
        if args[0]=='compose' and args[-1]=='db':
            self.events.append(('metrics-docker',args))
            if self.fail_database:
                self.fail_database=False
                self.containers[1]['State']['Running']=False
                raise host.GuardError('Injected database startup failure')
            self.containers[1]['Config']['Cmd']=host.read_json(host.ROOT/'compose.json')['services']['db'].get('command',['postgres'])
            self.containers[1]['State']['Running']=True
            return b''
        return super().docker(*args,**kwargs)

    def sql(self,database,statement):
        if 'count(*) FROM pg_extension' in statement:
            return '1' if self.extension else '0'
        if 'count(*) FROM pg_namespace' in statement:
            return '1' if self.schema else '0'
        if statement=='SHOW shared_preload_libraries;':
            return 'pg_stat_statements' if self.containers[1]['Config']['Cmd']==host.METRICS_COMMAND else ''
        if 'SELECT coalesce((SELECT extnamespace' in statement:
            return 'instantflow_benchmark_metrics' if self.extension else ''
        if 'CREATE SCHEMA IF NOT EXISTS' in statement:
            self.schema=True
            if self.fail_extension:
                self.fail_extension=False
                raise host.GuardError('Injected extension failure')
            self.extension=True
            return ''
        if 'DROP EXTENSION IF EXISTS' in statement:
            self.extension=False
            self.schema=False
            return ''
        if 'has_schema_privilege' in statement:
            return 't'
        if statement.startswith('DROP DATABASE IF EXISTS'):
            self.extension=False
            self.schema=False
        return super().sql(database,statement)


class SetupTest(unittest.TestCase):
    write=fixture.BenchmarkHostTest.write

    def setUp(self):
        fixture.BenchmarkHostTest.setUp(self)
        patcher=patch.object(metrics,'capture',return_value={'statements_available':True,
            'settings':{'track_io_timing':'on','track_wal_io_timing':'on'}})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.controller=SetupHost(self.root)

    def test_enables_only_fixed_database_settings_and_preserves_application_inventory(self):
        original=copy.deepcopy(self.controller.live_counts)
        result=self.controller.enable()
        self.assertEqual(result['status'],'enabled')
        self.assertEqual(self.controller.live_counts,original)
        self.assertEqual(self.controller.containers[1]['Config']['Cmd'],host.METRICS_COMMAND)
        self.assertTrue(self.controller.extension)
        self.assertFalse((self.root/'pending-metrics.json').exists())
        self.controller.guard()
        self.assertEqual(self.controller.enable()['status'],'already_enabled')
        self.assertFalse(any(e[0]=='database-mutation' for e in self.controller.events))

    def test_database_or_extension_failure_restores_previous_configuration(self):
        for field in ['fail_database','fail_extension']:
            setattr(self.controller,field,True)
            with self.assertRaisesRegex(host.GuardError,'previous configuration and application recovered'):
                self.controller.enable()
            self.assertEqual(self.controller.containers[1]['Config']['Cmd'],['postgres'])
            self.assertFalse(self.controller.extension)
            self.assertFalse(self.controller.schema)
            self.assertEqual(self.controller.live_counts['tickets'],15)
            self.controller.guard()

    def test_incomplete_recovery_blocks_other_commands_and_can_be_retried(self):
        self.controller.fail_database=True
        with patch.object(self.controller,'recover_metrics',side_effect=host.GuardError('unavailable')):
            with self.assertRaisesRegex(host.GuardError,'recovery incomplete'):
                self.controller.enable()
        with self.assertRaisesRegex(host.GuardError,'metrics setup'):
            self.controller.guard()
        self.controller.recover_metrics()
        self.controller.guard()

    def test_existing_unmanaged_extension_or_schema_is_never_overwritten(self):
        for field in ['extension','schema']:
            setattr(self.controller,field,True)
            with self.assertRaisesRegex(host.GuardError,'unmanaged'):
                self.controller.enable()
            setattr(self.controller,field,False)
        self.assertFalse(any(e[0] in {'database-mutation','metrics-docker'} for e in self.controller.events))

    def test_frozen_fixture_restore_reinstalls_private_statistics_extension(self):
        self.controller.enable()
        result=self.controller.switch(host.baseline_application(),fixture=True)
        self.assertTrue(self.controller.extension)
        self.assertEqual(self.controller.live_counts['tickets'],12)
        self.controller.switch(host.baseline_application(),restore_id=result['recovery_snapshot'])
        self.assertTrue(self.controller.extension)
        self.assertEqual(self.controller.live_counts['tickets'],15)

    def test_unknown_postgres_command_or_mounted_volume_refused_before_lifecycle_changes(self):
        for key,value in [('command',['postgres','-c','fsync=off']),('volumes',['serving:/var/lib/postgresql/data'])]:
            changed=copy.deepcopy(self.config)
            changed['services']['db'][key]=value
            self.write('compose.json',__import__('json').dumps(changed))
            with self.assertRaises(host.GuardError):
                self.controller.enable()
            self.assertFalse(any(e[0]=='metrics-docker' for e in self.controller.events))
