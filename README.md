BaseX utility functions
=======================

This module contains a variety of utillity functions that proved to be useful in some of the projects
At [ACDH-CH](https://www.oeaw.ac.at/acdh)

Another kind of eval functions
------------------------------

This module contains a few wrappers aroung jobs:eval and jobs:wait to make it easy to write small
snippets of XQuery containing a lot or all otherwise variable data as literals.
The reason this is useful is BaseX' straight forward and easy to understand locking mechanism:
Whenever the parser can't determine which databases are actually used by a query a global read lock
is acquired. In case of updating queries a global write lock is acquired.
In RestXQ functions this can severly impect how you can design your RESTful API. Furthermore it
is easy to overlook holding a global lock so no other write or read operations can take place.
The API seems stuck.

BaseX' locking design is sane and easy to understand so usually it is best to be left alone.
The parser sometimes seems to give up on finding the collection/DB actually used very fast
but looking as a human through ones code is not the parsers perspective so this is also good
enough most of the time.

The eval functions in this module nevertheless allow a batch of smaller XQueries to be scripted
using a larger XQuery and so the RestXQ API design is no longer dictated by the BaseX' locking.
Also it is more likely to hold only a lock to a particular database. At least such XQuery snippets
most of the time can be created.

This module actually predates BaseX' enforce index feature so it was also used to make it easier
for the parser to "see" that it can use indexes of some DB.

There are also two evals functions that execute a sequence of similar (probably generated) XQueries
in batches and return the result er errors of all of the XQueries passed to the function.
One use of this is for example to query a few hundred DBs containing similar data that was split
so updates to a particular part of the data will not exhaust resources and/or take forever to
finish (e. g. because rebuilding the indices takes a long time for all the data).

RestXQ utility functions
------------------------

This module contains

* a function to decode a Basic Auth header to username:password
* a function to get the correct base URI when BaseX is behind a reverse proxy
* a function to get the correct scheme and hostname when BaseX is behind a reverse proxy

Functions to deal with a huge amount of nodes returned from a query
-------------------------------------------------------------------

We had a case where a RestXQ initiated query would in the worst case return a few million
result nodes (from a few hundred DBs). This would normally lead to all the nodes
being serialized in memory an so would exhaust the memory.

To handle this situation there are functions in this module to convert result nodes to XML
that represents the references (pre numbers) to those nodes plus some small data to sort
or filter them (dehydrate). Then only a small subsequence of those nodes is actually read from
the DBs and presented to the user (hydrate).

Get some XML document node or else another without global locking
-----------------------------------------------------------------

Two contained functions get one of two documents given as parameter without needing a global lock.
