# Verified clips (Godot 4.7 scratch import, 2026-09-16)

Every clip below imports with the body's exact 49-bone skeleton and, played on the body,
lands every bone within 0.1 mm of its own skeleton. Numbers are at `root_scale = 100`,
where the body is 1.00 unit tall: multiply by the final body height for metres.
`travel` is the horizontal distance the hips cover over the clip (the authored speed is
travel / length for a cycle); `bob` is the hips' vertical range.

| file | length s | travel | bob |
|---|---|---|---|
| AirLoop-MidAirFallingIdle | 0.700 | 0.000 | 0.001 |
| BowAim-AimingIdleWithBow | 3.767 | 0.000 | 0.003 |
| BowAimStrafeLeft-WalkingLeftWhileAimingWithBow | 1.200 | 0.701 | 0.035 |
| BowAimStrafeRight-WalkingRightWhileAimingWithBow | 1.300 | 0.751 | 0.035 |
| BowAimWalk-WalkingForwardWhileAimingWithBow | 1.200 | 0.544 | 0.035 |
| BowAimWalkBack-WalkingBackwardsWhileAimingWithBow | 1.467 | 0.544 | 0.036 |
| BowCarry-StandingIdleWithBow | 5.100 | 0.000 | 0.003 |
| BowDraw-ChargingBowForPowershot | 3.767 | 0.009 | 0.001 |
| BowEquip-EquippingBow | 0.900 | 0.004 | 0.050 |
| BowLoose-StandingAimFireArrow | 0.700 | 0.011 | 0.010 |
| BowReload-ReloadingBow | 1.033 | 0.011 | 0.027 |
| BowUnequip-DisarmingBow | 1.100 | 0.004 | 0.049 |
| Cast-OneHandedCastingSpellFowards | 2.300 | 0.000 | 0.051 |
| CastIdle-StandingIdleReadyToCastSpell | 1.867 | 0.000 | 0.019 |
| CrouchDown-StandingToCrouchingTransition | 1.500 | 0.016 | 0.192 |
| CrouchIdle-CrouchIdle-2 | 6.833 | 0.000 | 0.009 |
| CrouchStrafeLeft-WalkingLeftWhileCrouched-2 | 1.100 | 0.660 | 0.050 |
| CrouchStrafeRight-WalkingRightWhileCrouched-2 | 1.100 | 0.711 | 0.058 |
| CrouchUp-CrouchToStandTransition | 0.633 | 0.120 | 0.145 |
| CrouchWalk-CrouchedWalk | 1.033 | 0.577 | 0.049 |
| CrouchWalkBack-WalkingBackwardsWhileCrouched-2 | 1.167 | 0.601 | 0.033 |
| Death-DeathFromStandingIdle | 3.033 | 0.372 | 0.278 |
| Drink-MaleDrinking | 8.867 | 0.000 | 0.005 |
| Heal-CastingAHealingSpellWithOneHand | 2.667 | 0.000 | 0.036 |
| Hit-HitReaction | 0.433 | 0.000 | 0.005 |
| HitBack-LargeHitReactionFromTheBack | 1.667 | 0.636 | 0.081 |
| HitLeft-LargeHitReactionFromTheLeft | 1.567 | 0.493 | 0.037 |
| HitRight-LargeHitReactionFromTheRight | 1.633 | 0.440 | 0.019 |
| HitSmallBack-SmallHitReactionFromTheBack | 1.267 | 0.000 | 0.013 |
| HitSmallFront-SmallHitReactionFromTheFront | 1.200 | 0.000 | 0.010 |
| HitSmallLeft-SmallHitReactionFromTheLeft | 1.200 | 0.000 | 0.013 |
| HitSmallRight-SmallHitReactionFromTheRight | 1.000 | 0.000 | 0.010 |
| Idle-BreathingIdle | 9.933 | 0.000 | 0.010 |
| IdleLook-StandingIdleLookingAround-2 | 9.333 | 0.000 | 0.030 |
| JumpStart-JumpingUpFromActionIdleGameBlend | 0.233 | 0.012 | 0.020 |
| Land-JumpingDownFromFallingIdleGameBlend | 0.367 | 0.029 | 0.022 |
| LandHard-MidAirFallingToAHardLandingGameBlend | 2.000 | 0.044 | 0.164 |
| PickUp-PickingUpAnObject | 9.567 | 0.014 | 0.042 |
| Roll-DiveRollFromStanding-2 | 2.367 | 1.773 | 0.248 |
| Run-StandardRunning | 0.733 | 1.269 | 0.009 |
| RunBack-RunningBackwards | 0.767 | 0.637 | 0.029 |
| RunJump-ForwardRunningJump | 1.000 | 1.637 | 0.432 |
| Slide-RunningToSlideAndBackToRunning | 1.533 | 2.624 | 0.242 |
| SpearCarry-StandingIdleReadyToCastSpell | 1.867 | 0.000 | 0.019 |
| StrafeLeft-RunningStrafeToTheLeft-2 | 0.667 | 0.945 | 0.015 |
| StrafeRight-RunningStrafeToTheRight-1 | 0.667 | 0.945 | 0.016 |
| StrafeWalkLeft-WalkingStrafeToTheLeft-2 | 0.933 | 0.713 | 0.033 |
| StrafeWalkRight-WalkingStrafeToTheRight-1 | 0.933 | 0.712 | 0.033 |
| SwordCarry-GreatSwordIdle | 2.000 | 0.000 | 0.001 |
| SwordCombo-GreatSwordComboSlash | 3.533 | 1.240 | 0.104 |
| SwordDownSlash-GreatSwordDownwardSlash | 1.267 | 0.000 | 0.067 |
| SwordDraw-TransitionFromStandingToDrawingAGreatSword | 0.800 | 0.055 | 0.015 |
| SwordJumpAttack-GreatSwordJumpAttackFromRun | 2.167 | 1.269 | 0.131 |
| SwordPowerSlash-GreatSwordPowerSlash | 1.800 | 0.451 | 0.029 |
| SwordRun-GreatSwordRun | 0.600 | 1.027 | 0.031 |
| SwordRunBack-GreatSwordBacwardRun | 0.733 | 0.758 | 0.014 |
| SwordSheathe-TransitionFromIdleToSheathingAGreatSword-2 | 0.733 | 0.102 | 0.021 |
| SwordSpin-GreatSwordHighSpinAttackFromRun | 1.867 | 0.930 | 0.078 |
| SwordStrafeLeft-GreatSwordStrafeLeftRun | 0.567 | 0.532 | 0.030 |
| SwordStrafeRight-GreatSwordStrafeRightRun | 0.633 | 0.783 | 0.024 |
| SwordStrafeWalkLeft-GreatSwordStrafeLeftWalk | 1.100 | 0.507 | 0.019 |
| SwordStrafeWalkRight-GreatSwordStrafeRightWalk | 1.167 | 0.581 | 0.016 |
| SwordWalk-GreatSwordWalk | 1.367 | 0.593 | 0.024 |
| SwordWalkBack-GreatSwordBackwardWalk | 1.300 | 0.523 | 0.024 |
| Throw-SpearThrowObject | 2.300 | 0.007 | 0.080 |
| ThrowRun-ThrowGrenadeWhileRunning | 2.933 | 3.721 | 0.017 |
| ThrowWalk-ThrowingAGrenadeWhileWalking | 2.767 | 1.071 | 0.021 |
| Walk-StandardWalk | 1.167 | 0.715 | 0.032 |
| WalkBack-WalkingBackwards-2 | 1.200 | 0.533 | 0.030 |
