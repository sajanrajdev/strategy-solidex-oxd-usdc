from helpers.StrategyCoreResolver import StrategyCoreResolver
from rich.console import Console
from brownie import interface
from tabulate import tabulate
from helpers.utils import val

console = Console()

class StrategyResolver(StrategyCoreResolver):
    def get_strategy_destinations(self):
        """
        Track balances for all strategy implementations
        (Strategy Must Implement)
        """
        # E.G
        # strategy = self.manager.strategy
        # return {
        #     "gauge": strategy.gauge(),
        #     "mintr": strategy.mintr(),
        # }

        return {}

    def hook_after_confirm_withdraw(self, before, after, params):
        """
        Specifies extra check for ordinary operation on withdrawal
        Use this to verify that balances in the get_strategy_destinations are properly set
        """
        assert True

    def hook_after_confirm_deposit(self, before, after, params):
        """
        Specifies extra check for ordinary operation on deposit
        Use this to verify that balances in the get_strategy_destinations are properly set
        """
        assert True

    def hook_after_earn(self, before, after, params):
        """
        Specifies extra check for ordinary operation on earn
        Use this to verify that balances in the get_strategy_destinations are properly set
        """
        assert True

    def printState(self, event, keys):
        table = []
        nonAmounts = ["token", "destination", "blockNumber", "timestamp"]
        for key in keys:
            if key in nonAmounts:
                table.append([key, event[key]])
            else:
                table.append([key, val(event[key])])

        print(tabulate(table, headers=["account", "value"]))

    def confirm_harvest_events(self, before, after, tx):
        key = "PerformanceFeeGovernance"
        assert key in tx.events
        assert len(tx.events[key]) >= 1
        for event in tx.events[key]:
            keys = [
                "destination",
                "token",
                "amount",
                "blockNumber",
                "timestamp",
            ]
            for key in keys:
                assert key in event

            console.print(
                "[blue]== Solidex Strat harvest() PerformanceFeeGovernance State ==[/blue]"
            )
            self.printState(event, keys)

        key = "Harvest"
        assert key in tx.events
        assert len(tx.events[key]) == 1
        event = tx.events[key][0]
        keys = [
            "harvested",
        ]
        for key in keys:
            assert key in event

        console.print("[blue]== Helper Strat harvest() State ==[/blue]")
        self.printState(event, keys)

        key = "PerformanceFeeStrategist"
        assert key not in tx.events
        # Strategist performance fee is set to 0

    def confirm_harvest(self, before, after, tx):
        """
        Verfies that the Harvest produced yield and fees
        """
        console.print("=== Compare Harvest ===")
        self.confirm_harvest_events(before, after, tx)
        super().confirm_harvest(before, after, tx)

        valueGained = after.get("sett.pricePerFullShare") > before.get(
            "sett.pricePerFullShare"
        )

    def confirm_tend(self, before, after, tx):
        """
        Tend Should;
        - Increase the number of staked tended tokens in the strategy-specific mechanism
        - Reduce the number of tended tokens in the Strategy to zero

        (Strategy Must Implement)
        """
        assert True

    def add_entity_balances_for_tokens(self, calls, tokenKey, token, entities):
        entities["strategy"] = self.manager.strategy.address
        entities["lpDepositor"] = self.manager.strategy.lpDepositor()
        entities["baseV1Router01"] = self.manager.strategy.baseV1Router01()
        entities["gauge"] = "0x8E81Ec0d9C184e73746446DfB83F86C1156744d5"


        super().add_entity_balances_for_tokens(calls, tokenKey, token, entities)
        return calls

    def add_balances_snap(self, calls, entities):
        super().add_balances_snap(calls, entities)
        strategy = self.manager.strategy

        solid = interface.IERC20(strategy.solid())
        sex = interface.IERC20(strategy.sex())
        wftm = interface.IERC20(strategy.sex())
        usdc = interface.IERC20(strategy.usdc())
        oxd = interface.IERC20(strategy.oxd())

        calls = self.add_entity_balances_for_tokens(calls, "solid", solid, entities)
        calls = self.add_entity_balances_for_tokens(calls, "sex", sex, entities)
        calls = self.add_entity_balances_for_tokens(calls, "wftm", wftm, entities)
        calls = self.add_entity_balances_for_tokens(calls, "usdc", usdc, entities)
        calls = self.add_entity_balances_for_tokens(calls, "oxd", oxd, entities)
