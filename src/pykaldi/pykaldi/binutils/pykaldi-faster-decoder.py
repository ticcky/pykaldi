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


from pykaldi.utils import load_wav, wst2dict
from pykaldi.decoders import PykaldiFasterDecoder, DecoderCloser
import sys

# FIXME todo measure time of decode resp decode_once through profiler


def write_decoded(f, wav_name, word_ids, wst):
    if wst is not None:
        decoded = [wst[str(w)] for w in word_ids]
    else:
        decoded = [str(w) for w in word_ids]
    line = ' '.join([wav_name] + decoded + ['\n'])
    print >> sys.stderr, 'DEBUG %s' % line
    f.write(line)


def decode_once(d, pcm):
    d.frame_in(pcm, len(pcm) / 2)  # 16-bit audio so 1 sample_width = 2 chars
    ids, prob = d.decode(force_end_utt=True)
    return [word_id for (word_id, probability) in ids]


def decode(d, pcm):
    frame_len = (2 * audio_batch_size)  # 16-bit audio so 1 sample = 2 chars
    it, decoded = (len(pcm) / frame_len), []
    print >> sys.stderr, 'NUMBER of audio input frames: %d' % it
    for i in xrange(it):
        frame = pcm[i * frame_len:(i + 1) * frame_len]
        d.frame_in(frame, audio_batch_size)
        ids, prob = d.decode()
        decoded.extend(ids)
    d.frame_in(pcm[it * frame_len:], (len(pcm) - (it * frame_len)) / 2)
    ids, prob = d.decode(force_end_utt=True)
    decoded.extend(ids)
    return [word_id for word_id in decoded]


def decode_wrap(argv, audio_batch_size, wav_paths, file_output, wst=None):
    with DecoderCloser(PykaldiFasterDecoder(argv)) as d:
        for wav_name, wav_path in wav_paths:
            # 16-bit audio so 1 sample_width = 2 chars
            pcm = load_wav(wav_path, def_sample_width=2, def_sample_rate=16000)
            word_ids = decode(d, pcm)
            write_decoded(file_output, wav_name, word_ids, wst)


if __name__ == '__main__':
    audio_scp, audio_batch_size, dec_hypo = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    argv = sys.argv[4:]
    print >> sys.stderr, 'Python args: %s' % str(sys.argv)

    # Try to locate and extract wst argument
    wst = None
    for a in argv:
        if a.endswith('words.txt'):
            wst = wst2dict(a)

    # open audio_scp, decode and write to dec_hypo file
    with open(audio_scp, 'rb') as r:
        with open(dec_hypo, 'wb') as w:
            lines = r.readlines()
            scp = [tuple(line.strip().split(' ', 1)) for line in lines]
            decode_wrap(argv, audio_batch_size, scp, w, wst)