#pragma once

// Paper Fig.15 path: linear sub-models (LR). Set USE_NN=1 to enable libtorch NNs.
#ifndef USE_NN
#define USE_NN 0
#endif
#define USE_TNN 0

#if USE_TNN
#include "../../x_ml/src/nn/nn_tiny.hh"
#elif USE_NN
#include "../../x_ml/src/nn/mod.hh"
#include "./models/log_nn.hh"
#include "./models/map_nn.hh"
#endif

#include "../../x_ml/src/lr/mod.hh"
#include "../../x_ml/src/mv_lr.hh"
#include "./server/ar_key.hh"
#include "./server/map_key.hh"
#include "./server/tpcc_key.hh"

#include "../../xcache/src/page_tt_iter.hh"
#include "../../xcache/src/rmi_2.hh"
#include "../../xcache/src/samplers/mod.hh"

#include "../../../xkv_core/src/xtree/sorted_iter.hh"
/*!
  Defininations of the YCSB keytype, value type, B+Tree layout, etc
 */
namespace xstore {

using namespace xcache;
using namespace xml;
using namespace xkv::xtree;

// Default: 1-D keys from file (OSM / lognormal), matching paper Table 2 / Fig.15.
// For 2-D lon/lat (smap.txt): compile with -DUSE_MAP=1 -DUSE_LOG=0.
#ifndef USE_LOG
#define USE_LOG 1
#endif
#define USE_AR 0
#define USE_TPCC 0

#ifndef USE_MAP
#define USE_MAP 0
#endif

#if USE_LOG
using KK = XKey;
const usize D = 1;
#endif

#if USE_AR
using KK = ARKey;
const usize D = 2;
#endif

#if USE_TPCC
using KK = TPCCKey;
const usize D = 4;
#endif

#if USE_MAP
using KK = MapKey;
const usize D = 2;
#endif

template<usize N>
struct OpaqueVal
{
  char data[N];
};

const usize kNPageKey = 16;
using ValType = u64;
using DBTree = XTree<kNPageKey, KK, ValType>;
using DBTreeIter = XTreeIter<kNPageKey, KK, ValType>;
using DBTreeSIter = XTreeSIter<kNPageKey, KK, ValType>;

template<typename Key>
using MMLR = MvLR<D, Key>;

#if USE_MV
template<typename Key>
using SML = MMLR<Key>;
#endif

#if USE_NN
#if !USE_TNN
template<typename Key>
using TNN = NN<LogNet, DualLogNet, D, Key>;

template<typename Key>
using MNN = NN<MapNet, DualMapNet, D, Key>;
#else
template<typename Key>
using TNN = XNN<Key>;
#endif
template<typename Key>
using SML = MNN<Key>;
#endif

#if !USE_NN && !USE_MV
template<typename Key>
using SML = LR<Key>;
#endif

using XCache = LocalTwoRMI<LR, SML, KK>;

using TrainIter = XCacheTreeIter<kNPageKey, KK, ValType>;

template<typename Key>
using PS = PageSampler<kNPageKey, Key>;

using DBTreeV = XTree<kNPageKey, KK, FatPointer>;
using DBTreeIterV = XTreeIter<kNPageKey, KK, FatPointer>;
using TrainIterV = XCacheTreeIter<kNPageKey, KK, FatPointer>;

} // namespace xstore
