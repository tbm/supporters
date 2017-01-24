#!/usr/bin/env python3

import argparse
import collections
import csv
import os
import subprocess

import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'supporters.settings')
django.setup()
from supporters.models import Payment

COLUMNS = collections.OrderedDict([
    ('date', '%(format_date(date, "%Y-%m-%d"))'),
    ('entity', '%(quoted(meta("Entity")))'),
    ('payee', '%(quoted(payee))'),
    ('program', '%(quoted(meta("Program")))'),
    ('amount', '%(quoted(display_amount))'),
])

def parse_arguments(arglist):
    parser = argparse.ArgumentParser(prog='load_ledger')
    parser.add_argument(
        '--ledger-from-scratch', default=False, action='store_true',
        help="""By default, this script imports all Supporter payments,
        and you can narrow the set of payments it imports by providing
        additional search criteria as arguments. If you set this flag,
        the script will not use any default criteria, and only use the criteria
        you specify.""")
    parser.add_argument(
        '--ledger-command', default='ledger', metavar='COMMAND',
        help="Name or path of ledger executable")
    parser.add_argument(
        'ledger_arguments', default=[], nargs=argparse.REMAINDER,
        help="Additional Ledger search criteria for payments to import")
    args = parser.parse_args(arglist)
    if args.ledger_arguments and (args.ledger_arguments[0] == '--'):
        del args.ledger_arguments[0]
    base_cmdline = [
        args.ledger_command, 'csv',
        '--csv-format', ','.join(COLUMNS.values()) + '\n',
        '--sort', 'date',
    ]
    if args.ledger_from_scratch:
        args.ledger_cmdline = base_cmdline + args.ledger_arguments
    else:
        args.ledger_cmdline = (base_cmdline
                               + ['--limit', 'tag("Program") =~ /:Supporters:/']
                               + args.ledger_arguments
                               + ['/^Income:/'])
    return args

def load_ledger(ledger_cmdline):
    ledger_env = os.environ.copy()
    for lang_envvar in ['LC_ALL', 'LC_CTYPE', 'LANG']:
        try:
            current_language = ledger_env[lang_envvar].split('.', 1)[0]
        except KeyError:
            pass
        else:
            break
    else:
        lang_envvar = 'LC_CTYPE'
        current_language = 'en_US'
    ledger_env[lang_envvar] = current_language + '.utf8'
    ledger = subprocess.Popen(ledger_cmdline,
                              env=ledger_env,
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    ledger.stdin.close()
    with ledger, open(ledger.stdout.fileno(), encoding='utf-8', closefd=False) as stdout:
        yield from csv.reader(stdout)
    assert ledger.returncode == 0, "ledger subprocess failed"

def save_payments(row_source):
    with django.db.transaction.atomic():
        for row in row_source:
            kwargs = {colname: row[index] for index, colname in enumerate(COLUMNS)}
            Payment(**kwargs).save()

def main(arglist):
    args = parse_arguments(arglist)
    save_payments(load_ledger(args.ledger_cmdline))

if __name__ == '__main__':
    main(None)
