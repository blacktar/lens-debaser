#pragma once

#include <string>
#include "LDBOpticsParameters.h"

void RunLensDebaserMetal(void* commandQueue, int width, int height,
                         const LDBOpticsParameters& parameters,
                         const float* input, float* output,
                         const float* depthInput = nullptr);

std::string ChooseLensDebaserPresetToLoad();
std::string ChooseLensDebaserPresetToSave();
