import copy
import json
import unittest

import benchmark_host as host
import benchmark_metrics as metrics


def counters():
    return {"unix_time": 100, "database": {"datid": 42, "stats_reset": None, **dict.fromkeys(metrics.DATABASE_COUNTERS, 10)},
            "wal": {"stats_reset": "epoch", **dict.fromkeys(metrics.WAL_COUNTERS, 10)},
            "settings": {"track_io_timing": "off"}, "statements_available": False,
            "cpu_identity": {"web": {"id": "web", "started_at": "epoch"}, "db": {"id": "db", "started_at": "epoch"}},
            "cpu": {s:dict.fromkeys(metrics.CPU_COUNTERS, 10) for s in ["web", "db"]}}


class MetricsTest(unittest.TestCase):
    def test_deltas_are_counters_not_lifetime_totals_and_disabled_timing_is_explicit(self):
        before = counters()
        after = copy.deepcopy(before)
        after["unix_time"] += 10
        after["database"]["xact_commit"] += 25
        after["wal"]["wal_bytes"] += 2048
        after["cpu"]["db"]["usage_usec"] += 500000
        result = metrics.difference(before, after)
        self.assertEqual(result["database"]["xact_commit"], 25)
        self.assertEqual(result["wal"]["wal_bytes"], 2048)
        self.assertEqual(result["cpu"]["db"]["usage_usec"], 500000)
        self.assertFalse(result["statement_statistics_available"])
        self.assertEqual(result["settings"]["track_io_timing"], "off")
        self.assertNotIn("statements", result)

    def test_reset_changed_database_restart_or_decreasing_counter_invalidates_observation(self):
        before = counters()
        for path, value in [(('database','datid'),43), (('database','stats_reset'),'reset'),
                            (('wal','stats_reset'),'reset'), (('database','xact_commit'),1),
                            (('settings','track_io_timing'),'on'), (('cpu_identity','web'),{'id':'new'})]:
            after = copy.deepcopy(before)
            after['unix_time'] += 10
            after[path[0]][path[1]] = value
            with self.assertRaises(host.GuardError):
                metrics.difference(before, after)

    def test_statement_deltas_include_new_queries_but_refuse_eviction_or_reset(self):
        before = counters()
        before["statements_available"] = True
        query = {"query_id": "123", "toplevel": True, **dict.fromkeys(metrics.STATEMENT_COUNTERS, 10)}
        before["statements"] = {"info": {"dealloc":0,"stats_reset":"epoch"}, "queries":[query]}
        after = copy.deepcopy(before)
        after['unix_time'] += 10
        after['statements']['queries'][0]['calls'] += 4
        after['statements']['queries'][0]['total_exec_time'] += 12
        after['statements']['queries'].append({**query,'query_id':'456'})
        result=metrics.difference(before,after)
        self.assertEqual(sum(q['calls'] for q in result['statements']),14)
        for key, value in [('info',{'dealloc':1,'stats_reset':'epoch'}),('queries',[])]:
            changed=copy.deepcopy(after)
            changed['statements'][key]=value
            with self.assertRaises(host.GuardError):
                metrics.difference(before,changed)

    def test_capture_exports_only_selected_aggregate_fields_and_numeric_cpu_counters(self):
        calls=[]
        before=counters()
        class Controller:
            def sql(self,database,statement):
                calls.append(statement)
                self_case.assertEqual(database,host.DATABASE)
                if statement==metrics.ACTIVITY_SQL:
                    return json.dumps({'backends':[],'locks':[],'pending_outbox':{'count':0,'oldest_seconds':None}})
                self_case.assertEqual(statement,metrics.COUNTERS_SQL)
                return json.dumps({k:before[k] for k in ['database','wal','settings','statements_available']})
            def docker(self,*args,**kwargs):
                if args[0]=='inspect':
                    return b'{"id":"web","started_at":"epoch"}\n{"id":"db","started_at":"epoch"}\n'
                return '\n'.join(name+' 10' for name in metrics.CPU_COUNTERS).encode()
        self_case=self
        result=metrics.capture(Controller())
        self.assertEqual(result['cpu']['web']['usage_usec'],10)
        self.assertEqual(len(calls),2)
        self.assertNotIn('query,',metrics.STATEMENTS_SQL)
        self.assertNotIn('client_addr',metrics.ACTIVITY_SQL)
        self.assertIn("usename='instantflow_runtime'",metrics.ACTIVITY_SQL)
        self.assertIn('statement_timeout',metrics.ACTIVITY_SQL)

    def test_missing_cgroup_fields_are_an_error_not_zero_cpu(self):
        with self.assertRaises(host.GuardError):
            metrics.cpu_counters('usage_usec 10\n')
