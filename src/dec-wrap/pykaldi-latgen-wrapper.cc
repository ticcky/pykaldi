// -*- coding: utf-8 -*-
/* Copyright (c) 2013, Ondrej Platek, Ufal MFF UK <oplatek@ufal.mff.cuni.cz>
 *               2012-2013  Vassil Panayotov
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 * THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
 * WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
 * MERCHANTABLITY OR NON-INFRINGEMENT.
 * See the Apache 2 License for the specific language governing permissions and
 * limitations under the License. */

#include "feat/feature-mfcc.h"
#include "dec-wrap/pykaldi-utils.h"
#include "dec-wrap/pykaldi-audio-source.h"
#include "dec-wrap/pykaldi-latgen-wrapper.h"
#include "dec-wrap/pykaldi-feat-input.h"
#include "dec-wrap/pykaldi-decodable.h"
#include "dec-wrap/pykaldi-latgen-wrapper.h"
#include "dec-wrap/pykaldi-latgen-decoder.h"
#include "fstext/fstext-lib.h"
// debug
#include <fstream>
#include <iostream>


namespace kaldi {

void GmmLatgenWrapper::Deallocate() {
  delete audio; audio = NULL;
  delete mfcc; mfcc = NULL;
  delete feat_input; feat_input = NULL;
  delete feat_transform; feat_transform = NULL;
  delete feat_matrix; feat_matrix = NULL;
  delete decodable; decodable = NULL;
  delete trans_model; trans_model = NULL;
  delete amm; amm = NULL;
  delete decoder; decoder = NULL;
  delete decode_fst; decode_fst = NULL;
}

GmmLatgenWrapper::~GmmLatgenWrapper() {
  Deallocate();
}

size_t GmmLatgenWrapper::Decode(size_t max_frames) {
  return decoder->Decode(decodable, max_frames);
}


void GmmLatgenWrapper::FrameIn(unsigned char *frame, size_t frame_len) {
  audio->Write(frame, frame_len);
}


int GmmLatgenWrapper::GetBestPath(std::vector<int> &v_out) {
  Lattice lat;
  int num_frames = decoder->GetBestPath(&lat);
  return num_frames; 
}

int GmmLatgenWrapper::GetRawLattice(Lattice & lat) {
  bool ok = decoder->GetRawLattice(&lat);
  fst::Connect(&lat); // Will get rid of this later... shouldn't have any

  BaseFloat acoustic_scale = decodable->GetAcousticScale();
  if (acoustic_scale != 0.0) // We'll write the lattice without acoustic scaling
    fst::ScaleLattice(fst::AcousticLatticeScale(1.0 / acoustic_scale), &lat); 

  return ok;
}

int GmmLatgenWrapper::GetLattice(CompactLattice &clat) {
  bool ok = decoder->GetLattice(&clat);

  BaseFloat acoustic_scale = decodable->GetAcousticScale();
  if (acoustic_scale != 0.0) // We'll write the lattice without acoustic scaling
    fst::ScaleLattice(fst::AcousticLatticeScale(1.0 / acoustic_scale), &clat); 

  // DEBUG
  if (ok) {
    std::ofstream f;
    f.open("last.lat", std::ios::binary);
    fst::FstWriteOptions opts;  // in fst/fst.h
    clat.Write(f, opts);
    f.close();
  }
  return ok;
}


void GmmLatgenWrapper::PruneFinal() {
  decoder->PruneFinal();
}


void GmmLatgenWrapper::Reset(bool keep_buffer_data) {
  if (!keep_buffer_data) {
    audio->Reset();
    feat_input->Reset();
    feat_transform->Reset();
  }
  feat_matrix->Reset();
  decodable->Reset();
  decoder->Reset();
}


int GmmLatgenWrapper::Setup(int argc, char **argv) {
  try {
    KaldiDecoderGmmLatgenWrapperOptions wrapper_opts;
    PykaldiFeatureMatrixOptions feature_reading_opts;
    MfccOptions mfcc_opts;
    LatticeFasterDecoderConfig decoder_opts;
    DeltaFeaturesOptions delta_feat_opts;
    PykaldiBuffSourceOptions au_opts;

    // Parsing options
    ParseOptions po("Utterance segmentation is done on-the-fly.\n"
      "The delta/delta-delta(2-nd order) features are produced.\n\n"
      "Usage: decoder-binary-name [options] <model-in>"
      "<fst-in> <word-symbol-table> <silence-phones> \n\n"
      "Example: decoder-binary-name --max-active=4000 --beam=12.0 "
      "--acoustic-scale=0.0769 model HCLG.fst words.txt '1:2:3:4:5'");

    wrapper_opts.Register(&po);
    mfcc_opts.Register(&po);
    decoder_opts.Register(&po);
    feature_reading_opts.Register(&po);
    delta_feat_opts.Register(&po);
    au_opts.Register(&po);

    po.Read(argc, argv);
    if (po.NumArgs() != 4 && po.NumArgs() != 5) {
      po.PrintUsage();
      return 1;
    }
    if (po.NumArgs() == 4)
      if (wrapper_opts.left_context % delta_feat_opts.order != 0 ||
          wrapper_opts.left_context != wrapper_opts.right_context)
        KALDI_ERR << "Invalid left/right context parameters!";

    wrapper_opts.model_rxfilename = po.GetArg(1);
    wrapper_opts.fst_rxfilename = po.GetArg(2);
    wrapper_opts.word_syms_filename = po.GetArg(3);

    wrapper_opts.silence_phones = phones_to_vector(po.GetArg(4));
    wrapper_opts.lda_mat_rspecifier = po.GetOptArg(5);

    // Setting up components
    trans_model = new TransitionModel();
    amm = new AmDiagGmm();
    {
      bool binary;
      Input ki(wrapper_opts.model_rxfilename, &binary);
      trans_model->Read(ki.Stream(), binary);
      amm->Read(ki.Stream(), binary);
    }

    decode_fst = ReadDecodeGraph(wrapper_opts.fst_rxfilename);
    decoder = new PykaldiLatticeFasterDecoder(
                                    *decode_fst, decoder_opts);

    audio = new PykaldiBuffSource(au_opts);

    mfcc = new Mfcc(mfcc_opts);
    int32 frame_length = mfcc_opts.frame_opts.frame_length_ms;
    int32 frame_shift = mfcc_opts.frame_opts.frame_shift_ms;
    feat_input = new PykaldiFeInput<Mfcc>(audio, mfcc,
                               frame_length * (wrapper_opts.kSampleFreq / 1000),
                               frame_shift * (wrapper_opts.kSampleFreq / 1000));

    if (wrapper_opts.lda_mat_rspecifier != "") {
      bool binary_in;
      Matrix<BaseFloat> lda_transform;
      Input ki(wrapper_opts.lda_mat_rspecifier, &binary_in);
      lda_transform.Read(ki.Stream(), binary_in);
      // lda_transform is copied to PykaldiLdaInput
      feat_transform = new PykaldiLdaInput(feat_input,
                                lda_transform,
                                wrapper_opts.left_context, wrapper_opts.right_context);
    } else {
      feat_transform = new PykaldiDeltaInput(delta_feat_opts, feat_input);
    }

    feat_matrix = new PykaldiFeatureMatrix(feature_reading_opts,
                                       feat_transform);
    decodable = new PykaldiDecodableDiagGmmScaled(*amm,
                                            *trans_model,
                                            wrapper_opts.acoustic_scale, feat_matrix);

  } catch(const std::exception& e) {
    std::cerr << e.what();
    Deallocate();
    return 2;
  }
  return 0;
}

} // namespace kaldi
