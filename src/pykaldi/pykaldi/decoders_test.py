#!/usr/bin/env python
# Copyright (c) 2013, Ondrej Platek, Ufal MFF UK <oplatek@ufal.mff.cuni.cz>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License. #


import unittest
import os
# Just import this is a test ;-)
import pykaldi
from pykaldi.utils import load_wav
from pykaldi.binutils.online_decode import run_online_dec
from pykaldi.decoders import PykaldiFasterDecoder, DecoderCloser
from pykaldi.utils import get_voxforge_data


class TestPykaldiFasterDecoder(unittest.TestCase):
    def setUp(self):
        dir_path = os.path.realpath(os.path.dirname(__file__))
        self.wav_path = os.path.join(dir_path, 'audio', 'test.wav')
        get_voxforge_data(path=dir_path)
        p = os.path.join(dir_path, 'online-data', 'models', 'tri2a')
        self.argv = ['--verbose=0', '--max-active=4000', '--beam=12.0',
                     '--acoustic-scale=0.0769',
                     os.path.join(p, 'model'),
                     os.path.join(p, 'HCLG.fst'),
                     os.path.join(p, 'words.txt'),
                     '1:2:3:4:5']

    def test_version(self):
        print 'pykaldi %s' % (str(pykaldi.__version__))
        b, m, p = pykaldi.__version__
        self.assertTrue(b + m + p > 0)

    def test_git_revision(self):
        print 'pykaldi last commit: %s' % (str(pykaldi.__git_revision__))
        self.assertTrue(len(pykaldi.__git_revision__) == 40)

    def test_decode(self, num_it=200):
        with DecoderCloser(PykaldiFasterDecoder(self.argv)) as d:
            for i in xrange(num_it):
                d.decode()

    def test_finish_decoding(self, num_it=200):
        with DecoderCloser(PykaldiFasterDecoder(self.argv)) as d:
            for i in xrange(num_it):
                d.decode(force_end_utt=True)

    def test_wav(self, words_to_dec=3):
        pcm = load_wav(self.wav_path)
        # Test PykaldiFasterDecoder
        samples_per_frame = 2120
        word_ids, prob = run_online_dec(pcm, self.argv, samples_per_frame)
        print 'From %s decoded %d utt: %s' % (self.wav_path, len(word_ids), str(word_ids))
        self.assertTrue(len(word_ids) > words_to_dec,
                        'We have to decode at least %d words' % words_to_dec)
        self.assertAlmostEqual(
            prob, 1.0, 'Have we implemented the probability or sthing wrong returned')


if __name__ == '__main__':
    unittest.main()