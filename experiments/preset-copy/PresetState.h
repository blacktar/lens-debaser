#pragma once
// Included after Preset. Payload is host-persistent reference metadata, never render input.
static std::string encodePresetState(const Preset& p) {
    std::ostringstream out;out<<std::setprecision(17)<<"LDBPresetReference 1 "<<std::quoted(p.name)<<'\n';
    std::map<std::string,double> sorted(p.values.begin(),p.values.end());
    out<<sorted.size()<<'\n';for(const auto& item:sorted)out<<std::quoted(item.first)<<' '<<item.second<<'\n';
    auto array=[&](const auto& a){for(double x:a)out<<x<<' ';out<<'\n';};
    array(p.center);array(p.fieldCenter);array(p.transmission);array(p.glare);
    array(p.nearFocus);array(p.farFocus);array(p.anamorphicFlare);array(p.anamorphicFlareGhost);
    out<<p.apertureShape<<' '<<p.apertureBladeCount<<' '<<p.depthMode<<' '
       <<p.captureGate<<' '<<p.prismDistribution<<' '<<p.opticalDriftMode<<'\n';
#if defined(LDB_ENABLE_FRAME_RELATIVE)
    out<<p.effectSize<<'\n';
#endif
#if defined(LDB_ENABLE_PROJECTION)
    out<<p.projectionModel<<' '<<p.projectionFraming<<'\n';
#endif
#if defined(LDB_ENABLE_FINAL_FRAMING)
    out<<p.finalFramingMode<<'\n';
#endif
    return out.str();
}
static bool decodePresetState(const std::string& data,Preset& result) {
    if(data.size()>131072)return false;
    std::istringstream in(data);std::string magic;int version=0;Preset p;size_t count=0;
    if(!(in>>magic>>version>>std::quoted(p.name))||magic!="LDBPresetReference"||version!=1||p.name.size()>4096)return false;
    if(!(in>>count)||count>512)return false;
    for(size_t n=0;n<count;n++) {
        std::string key;double value;
        if(!(in>>std::quoted(key)>>value)||key.size()>128||!std::isfinite(value)||!p.values.emplace(key,value).second)return false;
    }
    auto array=[&](auto& a){for(double& x:a)if(!(in>>x)||!std::isfinite(x))return false;return true;};
    if(!array(p.center)||!array(p.fieldCenter)||!array(p.transmission)||!array(p.glare)||
       !array(p.nearFocus)||!array(p.farFocus)||!array(p.anamorphicFlare)||!array(p.anamorphicFlareGhost))return false;
    if(!(in>>p.apertureShape>>p.apertureBladeCount>>p.depthMode>>p.captureGate>>p.prismDistribution>>p.opticalDriftMode))return false;
#if defined(LDB_ENABLE_FRAME_RELATIVE)
    if(!(in>>p.effectSize))return false;
#endif
#if defined(LDB_ENABLE_PROJECTION)
    if(!(in>>p.projectionModel>>p.projectionFraming))return false;
#endif
#if defined(LDB_ENABLE_FINAL_FRAMING)
    if(!(in>>p.finalFramingMode))return false;
#endif
    in>>std::ws;if(!in.eof())return false;
    result=std::move(p);return true;
}

static std::string encodePresetLibrary(const std::vector<Preset>& presets,int active) {
    std::ostringstream out;out<<"LDBPresetLibrary 1 "<<presets.size()<<' '<<active<<'\n';
    for(const auto& p:presets)out<<std::quoted(encodePresetState(p))<<'\n';
    return out.str();
}
static bool decodePresetLibrary(const std::string& data,std::vector<Preset>& result,int& selected) {
    if(data.size()>8*1024*1024)return false;
    std::istringstream in(data);std::string magic;int version,active;size_t count;
    if(!(in>>magic>>version>>count>>active)||magic!="LDBPresetLibrary"||version!=1||count==0||count>512||active< -2||(active>=0&&size_t(active)>=count))return false;
    std::vector<Preset> parsed;
    for(size_t i=0;i<count;i++) {
        std::string value;Preset p;
        if(!(in>>std::quoted(value))||!decodePresetState(value,p))return false;
        parsed.push_back(std::move(p));
    }
    in>>std::ws;if(!in.eof())return false;
    result=std::move(parsed);selected=active;return true;
}
