#pragma once
#ifdef LDB_RESOLVE_PARAMETER_AUDIT
#include "LDBOpticsParameters.h"
#include <filesystem>
#include <fstream>
#include <mutex>
#include <cstring>
#include <iomanip>
#include <unordered_map>
// Compiled only into the separate audit identity. No normal-product logging.
inline void LDBRecordResolveParameters(const char* stage,const LDBOpticsParameters& p,unsigned width,unsigned height) {
 static std::mutex lock;std::lock_guard<std::mutex> guard(lock);
 static std::unordered_map<std::string,std::string> previous;static unsigned records=0;
 unsigned char semantic[sizeof(p)];std::memcpy(semantic,&p,sizeof(p));
 // Ignore SIMD float3 padding: it is not a parameter and may be uninitialized.
 for(unsigned offset : {172u,204u,300u,332u,444u,716u})
  std::memset(semantic+offset,0,4);
 std::string slot=std::string(stage)+":"+std::to_string(width)+"x"+std::to_string(height);
 std::string key(reinterpret_cast<const char*>(semantic),sizeof(p));
 if(key==previous[slot]||records>=1000)return;previous[slot]=key;++records;
 const std::filesystem::path root=LDB_RESOLVE_AUDIT_OUTPUT;
 std::filesystem::create_directories(root);
 std::ofstream out(root/"resolve-parameters.jsonl",std::ios::app);
 out<<std::setprecision(9)<<"{\"stage\":\""<<stage<<"\",\"width\":"<<width<<",\"height\":"<<height
 <<",\"apertureResponse\":"<<p.apertureResponse<<",\"apertureRadius\":"<<p.apertureRadius
 <<",\"opticalDriftAmount\":"<<p.opticalDriftAmount<<",\"effectBlend\":"<<p.effectBlend
 <<",\"renderPixelScale\":"<<p.renderPixelScale<<",\"workingColorSpace\":"<<p.workingColorSpace
 <<",\"processingFlags\":"<<p.processingFlags<<",\"depthMode\":"<<p.depthMode
 <<",\"captureInfluence\":"<<p.captureInfluence<<",\"lookInfluence\":"<<p.lookInfluence
 <<",\"cornerSharpnessLoss\":"<<p.cornerSharpnessLoss<<",\"fieldCurvature\":"<<p.fieldCurvature
 <<",\"projectionAmount\":"<<p.reservedV4_3<<",\"projectionModel\":"<<p.reservedV4_4
 <<",\"abi_hex\":\"";
 const auto* bytes=reinterpret_cast<const unsigned char*>(&p);
 for(unsigned i=0;i<sizeof(p);++i)out<<std::hex<<std::setw(2)<<std::setfill('0')<<unsigned(bytes[i]);
 out<<"\"}\n";
}
#endif
