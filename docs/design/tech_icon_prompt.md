# Tech Tree Icon Generation Prompt

Reusable prompt template for generating consistent technology tree icons for Roots of Reason.

## Base Prompt (copy and customize per tech)

```
Create a game technology icon for a civilization RTS game.

STYLE REQUIREMENTS:
- 128x128 pixel icon (or generate at 512x512 for downscaling)
- Flat design with subtle depth — no photorealism, no 3D rendering
- Bold, clean shapes with 2-3px dark outlines
- Limited palette: 4-5 colors per icon maximum
- Circular or rounded-square frame with age-appropriate border color
- Slight inner glow or vignette to pop against dark UI backgrounds
- No text, no labels, no letters — symbol only
- Consistent lighting: top-left light source, subtle bottom-right shadow

AGE COLOR SCHEME (use for border tint and color temperature):
- Stone Age: warm earth tones — ochre (#C4903D), sienna (#A0522D), charcoal (#36454F)
- Bronze Age: amber and copper — bronze (#CD7F32), warm gold (#DAA520), clay (#B66A50)
- Iron Age: cool steel and olive — iron gray (#696969), olive (#708238), deep blue (#2C3E6B)
- Medieval Age: royal and muted — burgundy (#722F37), castle gray (#8B8589), forest green (#228B22)
- Industrial Age: smoke and fire — brick red (#CB4154), iron black (#3D3D3D), amber (#FFBF00)
- Information Age: digital cool — steel blue (#4682B4), white (#F0F0F0), electric cyan (#00CED1)
- Singularity Age: neon and holographic — neon cyan (#00FFFF), violet (#8A2BE2), white (#FFFFFF), with subtle iridescent sheen

ICON SUBJECT: [TECH_NAME]
AGE: [AGE_NAME]
SYMBOL DESCRIPTION: [Describe the central symbol — e.g., "a sharpened flint arrowhead" or "a double helix DNA strand"]
```

## Per-Tech Symbol Guide

### Stone Age
| Tech | Symbol Description |
|------|-------------------|
| Stone Tools | A sharpened flint hand-axe, angled as if just knapped |
| Fire Mastery | A stylized campfire with three flames, embers rising |
| Animal Husbandry | A sheep silhouette inside a fenced circle |
| Basket Weaving | A woven basket with crosshatch pattern, wheat stalks peeking out |

### Bronze Age
| Tech | Symbol Description |
|------|-------------------|
| Bronze Working | A bronze sword crossed with a hammer over an anvil |
| Writing | A clay tablet with cuneiform marks, a stylus beside it |
| Pottery | A ceramic amphora with decorative band |
| Irrigation | A water channel splitting into three streams feeding crops |
| Masonry | Stacked cut stone blocks forming a wall corner |
| Sailing | A single-mast reed boat on stylized waves |

### Iron Age
| Tech | Symbol Description |
|------|-------------------|
| Iron Working | A glowing iron ingot on an anvil with sparks |
| Philosophy | An owl perched on an open scroll |
| Mathematics | A compass and set square overlapping, geometric shapes |
| Currency | A stack of round coins with embossed symbols |
| Engineering | An aqueduct arch with water flowing through |
| Code of Laws | A stone tablet with carved text lines, scales of justice |
| Trireme | A war galley with triple oar rows, ram prow visible |
| Herbalism | A mortar and pestle with leafy herbs, green glow |

### Medieval Age
| Tech | Symbol Description |
|------|-------------------|
| Steel Working | A gleaming steel blade being folded on an anvil |
| Feudalism | A castle tower with a banner and a kneeling figure |
| Compass | A magnetic compass with cardinal directions, needle pointing north |
| Printing Press | A wooden press with a sheet of paper emerging |
| Guilds | A shield with crossed tools — hammer, trowel, and needle |
| Castle Architecture | A concentric castle with twin towers and portcullis |
| Gunpowder | A barrel of black powder with a lit fuse, sparks |
| Banking | A vault door ajar with gold coins visible inside |
| Shipbuilding | A ship hull on construction stocks with timber frame |
| Crop Rotation | Four field quadrants showing different crops in rotation |

### Industrial Age
| Tech | Symbol Description |
|------|-------------------|
| Steam Power | A steam engine piston with billowing steam cloud |
| Rifling | A rifle barrel cross-section showing spiral grooves |
| Railroad | Railroad tracks converging to a vanishing point with a steam locomotive |
| Electricity | A light bulb with lightning bolt, glowing filament |
| Steel Production | A Bessemer converter pouring molten steel |
| Chemistry | An Erlenmeyer flask with bubbling colored liquid |
| Sanitation | A water pipe with clean water droplets, a checkmark |
| Pasteurization | A milk bottle with a thermometer and heat waves |
| Vaccines | A syringe with a shield emblem, protective glow |
| Assembly Line | A conveyor belt with identical products in sequence |
| Dynamite | Three bundled dynamite sticks with lit fuse |
| Civil Service | A government building dome with a merit badge star |
| Ballistics | An artillery shell on a parabolic trajectory arc |

### Information Age
| Tech | Symbol Description |
|------|-------------------|
| Atomic Theory | An atom with electron orbits around a nucleus |
| Computing Theory | A Turing machine tape with binary digits, cog overlay |
| Transistors | A simplified transistor schematic symbol with silicon chip |
| Nuclear Fission | A split atom with energy rays radiating outward |
| Rocketry | A rocket in vertical ascent with exhaust plume |
| Satellite | A satellite orbiting a small globe with signal waves |
| Semiconductor Fab | A microchip die with circuit trace patterns |
| Internet | A globe wrapped in network connection lines, nodes glowing |
| Machine Learning | A brain with circuit pathways, one half organic, one half digital |
| Statistics | A bell curve graph with data points |
| Radar | A radar dish emitting concentric signal rings |
| Guided Missiles | A missile with targeting crosshair and trajectory line |
| Antibiotics | A pill capsule with a red cross and bacterial shapes being destroyed |
| Genetics | A double helix DNA strand with glowing segments |
| Cybersecurity | A digital shield with a lock icon, matrix-style code background |

### Singularity Age
| Tech | Symbol Description |
|------|-------------------|
| Neural Networks | Interconnected nodes in layers, signals flowing left to right |
| Big Data | Streams of data flowing into a funnel, crystallizing into a diamond |
| Parallel Computing | Multiple processor cores arranged in a grid, all lit up |
| Deep Learning | Stacked neural network layers with increasing abstraction depth |
| Quantum Computing | A qubit sphere (Bloch sphere) with superposition arrows |
| Robotics | A robotic arm assembling a gear, precision and strength |
| Transformer Architecture | An attention matrix pattern with "connections" highlighted — abstract and geometric |
| Alignment Research | A handshake between a human hand and a circuit-board hand, enclosed in a glowing circle |

## Batch Generation Workflow

1. Copy the base prompt
2. Fill in `[TECH_NAME]`, `[AGE_NAME]`, and `[SYMBOL_DESCRIPTION]` from the table above
3. Generate at 512x512, then downscale to 128x128 with bilinear filtering
4. Save as `assets/ui/tech_icons/{tech_id}.png` (snake_case matching tech_tree.json IDs)
5. Verify all 64 icons exist and match the age color temperature

## Example Complete Prompt

```
Create a game technology icon for a civilization RTS game.

STYLE REQUIREMENTS:
- 128x128 pixel icon (or generate at 512x512 for downscaling)
- Flat design with subtle depth — no photorealism, no 3D rendering
- Bold, clean shapes with 2-3px dark outlines
- Limited palette: 4-5 colors per icon maximum
- Circular or rounded-square frame with age-appropriate border color
- Slight inner glow or vignette to pop against dark UI backgrounds
- No text, no labels, no letters — symbol only
- Consistent lighting: top-left light source, subtle bottom-right shadow

AGE COLOR SCHEME (use for border tint and color temperature):
- Singularity Age: neon cyan (#00FFFF), violet (#8A2BE2), white (#FFFFFF), with subtle iridescent sheen

ICON SUBJECT: Alignment Research
AGE: Singularity Age
SYMBOL DESCRIPTION: A handshake between a human hand and a circuit-board hand, enclosed in a glowing circle
```
