Pykaldi - fork of Kaldi
=======================

Summary
-------
* Goal: Create a Python wrapper around Kaldi decoders suitable for real-time decoding in dialog systems.
* Based on the `Svn trunk of Kaldi project <svn://svn.code.sf.net/p/kaldi/code/trunk>`_ which is mirrored to branch ``svn-mirror``.
* There is also a new Kaldi recipe for training acoustic models. 
  See `egs/kaldi-vystadial-recipe <egs/kaldi-vystadial-recipe>`_ 
  and `README.rst <egs/kaldi-vystadial-recipe/README.rst>`_!
* The python wrapper is at `src/pykaldi <src/pykaldi>`_. 
  Read the `README.rst <src/pykaldi/README.rst>`_!


Install
-------

..  image:: https://travis-ci.org/UFAL-DSG/pykaldi.png
    :target: https://travis-ci.org/UFAL-DSG/pykaldi


* Read `INSTALL.rst <./INSTALL.rst>`_ and `INSTALL <./INSTALL>`_ first!
* `INSTALL.rst <./INSTALL.rst>`_ contains instructions specific for Pykaldi. 
  `INSTALL <./INSTALL>`_ stores general instructions for Kaldi.


Other info
----------
* Pykaldi is developed under `Vystadial project <https://sites.google.com/site/filipjurcicek/projects/vystadial>`_.
* The svn trunk is mirrored via ``git svn``. 
  Checkout tutorials: `Git svn <http://viget.com/extend/effectively-using-git-with-subversion>`_, 
  `Svn branch in git <http://ivanz.com/2009/01/15/selective-import-of-svn-branches-into-a-gitgit-svn-repository>`_

LICENSE
--------
* Pykaldi is released under the `Apache license, Version 2.0 <http://www.apache.org/licenses/LICENSE-2.0>`_, which is also used by Kaldi itself. 
* We also want to publicly release the training data for the recipe in the autumn 2013.