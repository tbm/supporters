Python Supporter Database
=========================

This directory contains a Python module and set of scripts to load Supporter payment information into a database, and query that information using consistent business logic.

As of today it only imports payment information from Ledger.  It doesn't know about the supplemental Supporter database with contact information, requests, etc.  For that, use the Perl module.

Getting Started
---------------

You'll need Python 3, Django, and Ledger::

  # apt install python3 python3-django ledger

Create the database::

  $ ./manage.py makemigrations supporters
  $ ./manage.py migrate

Load data from Ledger.  Depending on how you've configured Ledger, you may need to tell it where to find the books with Supporter payments.  You can pass additional arguments to configure how the import is done; run the script with the ``--help`` flag for details.  A typical first import looks like::

  $ ./load_ledger.py -- --file /path/to/supporters.ledger

Importing More Data
~~~~~~~~~~~~~~~~~~~

If you run ``load_ledger.py`` multiple times, each run will add the imported transactions to the database each time.  It doesn't know how to import "new" data only yet.

If you can specify what "new" data is with Ledger search criteria, you can use those to add new payments to the database.  For example, if you have all payments through 2016, and now you want to import payments from 2017, you might run::

  $ ./load_ledger.py -- --begin 2017-01-01

If you're unsure, you can just remove the ``db.sqlite3`` file, then recreate the database following the steps in the `Getting Started`_ section.

Reports
-------

Other scripts in this directory generate reports from the payment database.  You can run any script with the ``--help`` flag to learn more about what it does and how to run it.
