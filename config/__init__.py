## Ideally, they have one file with the settings for the strat and deployment
## This file would allow them to configure so they can test, deploy and interact with the strategy
from dotmap import DotMap

BADGER_DEV_MULTISIG = "0x4c56ee3295042f8A5dfC83e770a21c707CB46f5b"

sett_config = DotMap(
    native = DotMap(
        oxdUsdcLp = DotMap(
            WANT = "0xEaFB5Ae6eEa34954eE5e5a27B068B8705CE926a6",  ## OXD/USDC LP
            LP_COMPONENT =  "0xD31Fcd1f7Ba190dBc75354046F6024A9b86014d7",  ## SEX
            REWARD_TOKEN = "0x888ef71766ca594ded1f0fa3ae64ed2941740a20",  ## SOLID
            WHALE = "0x8E81Ec0d9C184e73746446DfB83F86C1156744d5"
        )
    )
)

## Fees in Basis Points
DEFAULT_GOV_PERFORMANCE_FEE = 1500
DEFAULT_PERFORMANCE_FEE = 0
DEFAULT_WITHDRAWAL_FEE = 10

FEES = [DEFAULT_GOV_PERFORMANCE_FEE, DEFAULT_PERFORMANCE_FEE, DEFAULT_WITHDRAWAL_FEE]

BADGER_TREE = "0x89122c767A5F543e663DB536b603123225bc3823"

REGISTRY = "0xFda7eB6f8b7a9e9fCFd348042ae675d1d652454f"  # Multichain BadgerRegistry
