import unittest
import os

import psycopg2
import psycopg2.extras
import decimal

from .utils import DbTestBase


class TestTriggers(unittest.TestCase, DbTestBase):

    @classmethod
    def tearDownClass(cls):
        cls.conn.rollback()

    @classmethod
    def setUpClass(cls):
        pgservice = os.environ.get('PGSERVICE') or 'pg_qgep'
        cls.conn = psycopg2.connect("service={service}".format(service=pgservice))

    def test_last_modified(self):
        row = {
            'identifier': 'CO123',
            'level': decimal.Decimal('100.000'),
            'situation_geometry': self.execute('ST_SetSrid(ST_MakePoint(3000000, 1500000, 100), 2056)')
        }

        obj_id = self.insert_check('vw_cover', row)

        row = self.select('structure_part', obj_id)

        last_mod = row['last_modification']
        assert last_mod is not None, "Last modification not set on insert"

        row = {
            'identifier': 'CO1234',
        }

        self.update_check('structure_part', row, obj_id)

        row = self.select('structure_part', obj_id)
        assert last_mod != row['last_modification'], "Last modification not set on update (still {})".format(row['last_modification'])

        last_mod = row['last_modification']

        row = {
            'level': decimal.Decimal('300.000')
        }

        self.update_check('cover', row, obj_id)

        row = self.select('structure_part', obj_id)
        assert last_mod != row['last_modification'], "Last modification not set on update of child table (still {})".format(row['last_modification'])

    def test_identifier(self):
        row = {
            'co_level': decimal.Decimal('100.000'),
            'ws_type': 'manhole',
            'situation_geometry': self.execute('ST_SetSrid(ST_MakePoint(3000000, 1500000), 2056)')
        }

        obj_id = self.insert_check('vw_qgep_wastewater_structure', row)

        row = self.select('vw_qgep_wastewater_structure', obj_id)

        for r in row:
            print(r)

        row = self.select('structure_part', row['co_obj_id'])

        for r in row:
            print(r)

        identifier = row['identifier']
        assert identifier, "Identifier not set on insert: {}".format(repr(identifier))


if __name__ == '__main__':
    unittest.main()
