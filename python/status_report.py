#!/usr/bin/env python3

import argparse
import collections
import csv
import datetime
import functools
import os
import sys

import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'supporters.settings')
django.setup()
from supporters.models import Date, Payment, Supporter

MONTH_FMT = '%Y-%m'

def parse_arguments(arglist):
    parser = argparse.ArgumentParser(
        prog='status_report',
        description="Print a CSV report counting Supporters over time",
    )
    month_date = functools.partial(Date.strptime, fmt=MONTH_FMT)
    parser.add_argument(
        '--start-month', type=month_date, metavar='YYYY-MM',
        default=Payment.objects.order_by('date').first().date,
        help="First month in report")
    parser.add_argument(
        '--end-month', type=month_date, metavar='YYYY-MM',
        default=Date.today(),
        help="Last month in report")
    args = parser.parse_args(arglist)
    if args.end_month < args.start_month:
        parser.error("End month predates start month")
    return args

def count_tuple(counter):
    return (
        counter[Supporter.STATUS_NEW],
        counter[Supporter.STATUS_NEW] + counter[Supporter.STATUS_ACTIVE],
        counter[Supporter.STATUS_LAPSED],
        counter[Supporter.STATUS_LOST],
    )

def report_month(month):
    annuals = collections.Counter(Supporter(name).status(month)
                                  for name in Supporter.iter_entities(['Annual']))
    monthlies = collections.Counter(Supporter(name).status(month)
                                    for name in Supporter.iter_entities(['Monthly']))
    return ((month.strftime(MONTH_FMT),)
            + count_tuple(annuals)
            + count_tuple(monthlies)
            + count_tuple(annuals + monthlies))

def main(arglist):
    args = parse_arguments(arglist)
    out_csv = csv.writer(sys.stdout)
    out_csv.writerow((
        'Month',
        'Annual New', 'Annual Active', 'Annual Lapsed', 'Annual Lost',
        'Monthly New', 'Monthly Active', 'Monthly Lapsed', 'Monthly Lost',
        'Total New', 'Total Active', 'Total Lapsed', 'Total Lost',
    ))
    month = Date.from_pydate(args.start_month)
    while month <= args.end_month:
        out_csv.writerow(report_month(month))
        month = month.round_month_up()

if __name__ == '__main__':
    main(None)
