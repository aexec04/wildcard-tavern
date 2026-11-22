from PIL import Image
ref = Image.open('claude/reference/concept_t/full_reference.png').convert('RGB')
W, H = ref.size
im = ref.crop((int(0.33 * W), int(0.46 * H), int(0.67 * W), int(0.72 * H)))
im.save('art-wip/concept_t/tmp/probe_stage.png')
im = ref.crop((int(0.19 * W), int(0.66 * H), int(0.80 * W), int(0.95 * H)))
im.save('art-wip/concept_t/tmp/probe_hand.png')
