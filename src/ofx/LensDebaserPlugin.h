#pragma once

#include "ofxsImageEffect.h"

class LensDebaserPluginFactory : public OFX::PluginFactoryHelper<LensDebaserPluginFactory> {
public:
    LensDebaserPluginFactory();
    void load() override {}
    void unload() override {}
    void describe(OFX::ImageEffectDescriptor&) override;
    void describeInContext(OFX::ImageEffectDescriptor&, OFX::ContextEnum) override;
    OFX::ImageEffect* createInstance(OfxImageEffectHandle, OFX::ContextEnum) override;
};
