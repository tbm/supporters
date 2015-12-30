Mini Non-Profit Supporters and Donors Database
==============================================

"Supporters" is a small donor database for non-profit fundraising that uses
Ledger-CLI as a backend for accounting data.

While this system is used in production for Software Freedom Conservancy, the
code is likely only appropriate if you plan to do a lot of work on the
command-line.  Eventually, the ideal would be to refactor CiviCRM to support
the ideas and Ledger-CLI integration represented in this code.

Why Does This Exist?
--------------------

Conservancy needed a simple donor database and could not invest the resources
required to maintain a CiviCRM instance: most organizations that use CiviCRM
either pay for hosting or devote some amount of staff time its maintenance.
Conservancy could afford neither, but this weekend-hack version of a database
suits our needs (at least for now).

License Information
-------------------

See the file [LICENSE.md](LICENSE.md) for license information.

Common Tasks
------------

These are recipes for some common tasks that one might want to complete on
the command line with the Supporters database.

