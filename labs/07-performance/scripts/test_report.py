"""Regression checks for metrics that can silently mislead a benchmark report."""
import unittest
from unittest.mock import patch
import lab
from report import summary, deltas


class MetricsTest(unittest.TestCase):
    def test_snapshot_json_can_span_multiple_lines(self):
        with patch.object(lab, 'sql', return_value='{"statements": [{"calls": 1},\n {"calls": 2}]}'):
            self.assertEqual(len(lab.js('SELECT snapshot')['statements']), 2)

    def test_p95_is_nearest_rank_and_not_maximum(self):
        self.assertEqual(summary(list(range(1,101))), '50.500 / 95.000 / 28.866 (n=100)')

    def test_stats_reset_invalidates_window(self):
        self.assertFalse(deltas({'reset': {'stats_reset':'a'}}, {'reset':{'stats_reset':'b'}})['valid'])

    def test_counter_delta_and_new_query(self):
        def statement(calls, queryid=1):
            return dict(userid=1, dbid=1, queryid=queryid, calls=calls,total_exec_time=calls*2,
                        shared_blks_hit=calls*3,shared_blks_read=0,query='SELECT 1')
        before = dict(reset={}, statements=[statement(10)])
        after = dict(reset={}, statements=[statement(12),statement(3,2)])
        result = deltas(before,after)
        self.assertTrue(result['valid'])
        self.assertEqual([s['calls'] for s in result['statements']], [2,3])
        self.assertEqual(result['statements'][0]['total_exec_time'],4)

    def test_decreasing_counter_invalidates_window(self):
        base = dict(userid=1,dbid=1,queryid=1,query='SELECT 1',total_exec_time=1,shared_blks_hit=1,shared_blks_read=0)
        self.assertFalse(deltas(dict(reset={},statements=[dict(base,calls=2)]),dict(reset={},statements=[dict(base,calls=1)]))['valid'])


if __name__ == '__main__':
    unittest.main()
