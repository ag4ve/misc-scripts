#!/usr/bin/env python

import os
import glob
import json
from ripgrepy import Ripgrepy
from jinja2 import Template
import magic
from filehash import FileHash
from datetime import datetime
import argparse
import sqlite3

from pprint import pprint

description="""Personal file search script"""

parser = argparse.ArgumentParser(description=description)

parser.add_argument('--ex', dest='ex', action='store', type=str, required=True, help='Regex to match')
parser.add_argument('--path', dest='paths', action='extend', type=str, required=False, nargs='+', default=[], help='Paths to look in')
parser.add_argument('--describe', dest='describe', action='store_true', required=False, help='Show work')
parser.add_argument('--binary', dest='look_binary', action='store_true', required=False, help='Search in binary files')
parser.add_argument('--no-defaults', dest='no_defaults', action='store_true', required=False, help='Do not set default options')
parser.add_argument('--db', dest='db', action='store', required=False, help='Write a log to a sqlite database')
args = parser.parse_args()

# like PATH - separated with ':'
lib_dirs = (os.getenv('EX_LIBS') or os.getenv('HOME') + '/.config/ex_libs').split(':')
libs = sum([glob.glob(directory + '/*.json') for directory in lib_dirs if os.path.exists(directory)], [])

def_tmpl = """
{% for filename, data in output.items() -%}
  {{ "{:<20}".format(filename) }} \
  {{ "{:>25}".format(data.magic) }}  \
  {{ data.stat.st_mtime }}
{% endfor %}
"""
tmpl_str = (os.getenv('EX_TEMPLATE') or def_tmpl)

lookup_paths = args.paths if len(args.paths) else [os.getcwd()]

def main():
  ex_lookup = dict()
  for file in libs:
    with open(file, "r") as read_file:
      ex_lookup.update(json.load(read_file))

  ex = args.ex
  compiled = str(ex).format(**ex_lookup)

  if args.describe:
    pprint(compiled)

  rg = Ripgrepy(regex_pattern=compiled, path=lookup_paths.pop())

  for path in lookup_paths:
    rg = rg.glob(path)

  if not args.no_defaults:
    rg = rg.no_ignore().hidden().smart_case()

  if args.look_binary:
    rg = rg.text()

  rg_out = rg.json().run().as_dict

  if args.describe:
    pprint(rg_out)

  # ignore_case
  # engine(pcre2)
  # search_zip
  # regexp

  match_data = dict()
  for match in rg_out:
    filename = match['data']['path']['text']

    if filename not in match_data:
      s_obj = os.stat(filename)
      match_data[filename] = {
        'matches': list(),
        'magic': magic.from_file(filename, mime=True),
        # Map that calculate the epoch for all st_*time values
        'stat':  {k: datetime.fromtimestamp(getattr(s_obj, k)) if k.endswith('time') else getattr(s_obj, k) 
            for k in dir(s_obj) if k.startswith('st_')},
        'hashes': {hash: FileHash(hash).hash_file(filename) for hash in 
            ('crc32', 'md5', 'sha1', 'sha224', 'sha256', 'sha384', 'sha512')}
      }

    match_data[filename]['matches'].append({
      'line': match['data']['line_number'],
      'offsets': list(map(lambda x: {'start': x['start'], 'end': x['end']}, match['data']['submatches']))
    })

  print(Template(tmpl_str).render({"output": match_data}))

  return match_data

def sql_run(conn, queries):
  if len(queries) and conn is not None:
    try:
      cursor = conn.cursor()
      for tbl in queries:
        cursor.execute(tbl)
    except sqlite3.Error as e:
      if conn:
        conn.rollback()
      print(e)

def sql_import(db_file, data):
  conn = None
  try:
    conn = sqlite3.connect(db_file)
  except sqlite3.Error as e:
    print(e)

  tbl_opts = """
    PRAGMA foreign_keys = ON;
  """

  regex_tbl = """
    CREATE TABLE IF NOT EXISTS regex (
      id integer PRIMARY KEY AUTOINCREMENT,
      cli text NOT NULL,
      compiled text NOT NULL
    );
  """

  file_tbl = """
    CREATE TABLE IF NOT EXISTS file (
      id integer PRIMARY KEY AUTOINCREMENT,
      filename text NOT NULL
    );
  """

  regex_file_tbl = """
    CREATE TABLE IF NOT EXISTS regex_file (
      id integer PRIMARY KEY AUTOINCREMENT,
      regex_id integer NOT NULL,
      file_id integer NOT NULL,
      FOREIGN KEY (regex_id) REFERENCES regex (id),
      FOREIGN KEY (file_id) REFERENCES file (id)
    );
  """

  metadata_tbl = """
    CREATE TABLE IF NOT EXISTS regex_file (
      id integer PRIMARY KEY AUTOINCREMENT,
      magic text NOT NULL,
      atime text NOT NULL,
      ctime text NOT NULL,
      ntime text NOT NULL,
      file_id integer NOT NULL,
      FOREIGN KEY (file_id) REFERENCES file (id)
    );
  """

  matches_tbl = """
    CREATE TABLE IF NOT EXISTS regex_file (
      id integer PRIMARY KEY AUTOINCREMENT,
      line integer NOT NULL,
      start integer NOT NULL,
      end integer NOT NULL,
      file_id integer NOT NULL,
      FOREIGN KEY (file_id) REFERENCES file (id)
    );
  """

  run_log_tbl = """
    CREATE TABLE IF NOT EXISTS regex_file (
      id integer PRIMARY KEY AUTOINCREMENT,
      epoch integer NOT NULL,
      regex_id integer NOT NULL,
      file_id integer NOT NULL,
      metadata_id integer NOT NULL,
      FOREIGN KEY (regex_id) REFERENCES regex (id)
      FOREIGN KEY (file_id) REFERENCES file (id)
      FOREIGN KEY (metadata_id) REFERENCES metadata (id)
    );
  """

  sql_run(conn, (tbl_opts, regex_tbl, file_tbl, regex_file_tbl, metadata_tbl, matches_tbl, run_log_tbl))


if __name__ == '__main__':
  data = main()

  if args.db and data is not None:
    sql_import(args.db, data)

