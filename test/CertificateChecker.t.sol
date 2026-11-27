// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CertificateChecker} from "../src/CertificateChecker.sol";

/// @notice The pigeonhole formulas PHP(n + 1, n) are the textbook hard family for resolution. The
///         refutations below were found by tools/gen_refutation.py and are judged here by the contract;
///         for the small cases the result is cross-checked by counting models exhaustively. These are
///         known results, re-checked, not new ones.
contract CertificateCheckerTest is Test {
    CertificateChecker internal checker;

    // Steps as five bytes each: left index (2), right index (2), pivot variable (1).
    bytes internal constant PHP_3_2 =
        hex"000100060300090003020002000805000b0004040001000c03000d0003020002000705000f000504000900100200000011010012000e00";
    bytes internal constant PHP_4_3 =
        hex"00010010050016000a04001700040300020013080019000b07001a0005060001001b05001c000a04001d0004030002001108001f000d070020000506001600210400220004030019000d070024000506000300150b0026000e0a002700060900020028080029000d07002a000506000300140b002c000f0a002d0006090019002e07002f00050600010030050031002b040032000403001f000b0700340007060017003503001a0007060026000c0a00380008090002003908003a000b07003b000706002c000c0a003d000909001a003e060001003f050040000a040041003c030020000706000300120b0044000f0a0045000809001f00460700470007060044000e0a00490009090020004a060016004b04004c0048030000004d02004e004201004f003300";
    bytes internal constant PHP_5_4 =
        hex"0001002307002d001906002e000f05002f000504000200270b0031001a0a00320010090033000608000100340700350019060036000f050037000504000200240b0039001d0a003a001009003b000608002d003c06003d000f05003e0005040031001d0a004000100900410006080003002a0f0043001e0e004400110d004500070c000200460b0047001d0a00480010090049000608000300280f004b00200e004c00110d004d00070c0031004e0a004f001009005000060800010051070052004a060053000f0500540005040039001a0a00560013090057000608002e00580500590005040032001309005b0006080043001b0e005d00140d005e00070c0002005f0b0060001a0a00610013090062000608004b001b0e006400160d006500070c0032006609006700060800010068070069001906006a006305006b000504003a001309006d000608000300250f006f00200e007000140d007100070c003900720a00730013090074000608006f001e0e007600160d007700070c003a0078090079000608002d007a06007b007505007c0005040040001309007e000608004400140d008000070c000200810b0082001d0a00830013090084000608004c00140d008600070c003100870a00880013090089000608004300200e008b00140d008c00070c0004002c13008e002112008f0015110090000810000300910f009200200e009300140d009400070c0004002b13009600221200970015110098000810004300990e009a00140d009b00070c0002009c0b009d00950a009e001309009f000608004b001e0e00a100160d00a200070c004000a30900a4000608004400160d00a600070c008e001f1200a800171100a9000810000300aa0f00ab001e0e00ac00160d00ad00070c0096001f1200af00181100b0000810004400b10d00b200070c000200b30b00b4001d0a00b500ae0900b6000608004c00160d00b800070c000400291300ba00221200bb00171100bc000810004b00bd0e00be00160d00bf00070c00ba00211200c100181100c2000810004c00c30d00c400070c003100c50a00c600c00900c7000608000100c80700c900b70600ca00a00500cb000504005600100900cd000908002f00ce040033000908005d00110d00d1000a0c000200d20b00d3001a0a00d400100900d5000908006400110d00d7000c0c003300d808000100d90700da00190600db000f0500dc00d604003b000908007000110d00df000a0c003900e00a00e100100900e2000908007600110d00e4000c0c003b00e508002d00e60600e7000f0500e800e30400410009080045000a0c000200eb0b00ec001d0a00ed00100900ee000908004d000a0c003100f00a00f100100900f2000908008b00110d00f4000a0c008f00121100f6000b10000300f70f00f800200e00f900110d00fa000a0c009700121100fc000b10004300fd0e00fe00110d00ff000a0c000201000b010100fb0a0102001009010300090800a100110d0105000c0c00410106080045000c0c00a80012110109000d100003010a0f010b001e0e010c00110d010d000c0c00af001211010f000e10004501100c000201110b0112001d0a01130010090114010e08004d000c0c00bb0012110117000d10004b01180e011900110d011a000c0c00c1001211011c000e10004d011d0c0031011e0a011f0010090120011b08000101210701220115060123000f0501240104040057000908006f001b0e012700160d0128000a0c0056012909012a000908012700140d012c000c0c0057012d08002e012e05012f012b04005b000908005e000a0c000201320b0133001a0a013400130901350009080065000a0c00320137090138000908005d00160d013a000a0c008e001c12013c001711013d000b100003013e0f013f001b0e014000160d0141000a0c0096001c1201430018110144000b10005d01450d0146000a0c000201470b0148001a0a0149014209014a000908006400140d014c000c0c005b014d08005e000c0c013c0015110150000d10000301510f0152001b0e015300140d0154000c0c01430015110156000e10005e01570c000201580b0159001a0a015a001309015b0155080065000c0c00ba001c12015e001811015f000d10006401600d0161000c0c015e0017110163000e10006501640c00320165090166016208000101670701680019060169015c05016a014b04006d0009080071000a0c0039016d0a016e001309016f0009080077000a0c003a0171090172000908007000160d0174000a0c0004002613017600221201770017110178000b10006f01790e017a00160d017b000a0c0176002112017d001811017e000b100070017f0d0180000a0c003901810a0182017c090183000908007600140d0185000c0c006d0186080071000c0c01770015110189000d10006f018a0e018b00140d018c000c0c017d001511018e000e100071018f0c003901900a01910013090192018d080077000c0c0176001f1201950018110196000d10007601970d0198000c0c0195001711019a000e100077019b0c003a019c09019d019908002d019e06019f01930501a0018404000001a10301a2016b0201a301250101a400cc00";

    function setUp() public {
        checker = new CertificateChecker();
    }

    // ---------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------

    /// @dev Variable i * holes + j says pigeon i sits in hole j.
    function _php(uint256 pigeons, uint256 holes) internal pure returns (CertificateChecker.Clause[] memory cnf) {
        cnf = new CertificateChecker.Clause[](pigeons + holes * pigeons * (pigeons - 1) / 2);
        uint256 n;
        for (uint256 i = 0; i < pigeons; ++i) {
            uint256 pos;
            for (uint256 j = 0; j < holes; ++j) {
                pos |= uint256(1) << (i * holes + j);
            }
            cnf[n++] = CertificateChecker.Clause({pos: pos, neg: 0});
        }
        for (uint256 j = 0; j < holes; ++j) {
            for (uint256 i = 0; i < pigeons; ++i) {
                for (uint256 k = i + 1; k < pigeons; ++k) {
                    uint256 neg = (uint256(1) << (i * holes + j)) | (uint256(1) << (k * holes + j));
                    cnf[n++] = CertificateChecker.Clause({pos: 0, neg: neg});
                }
            }
        }
    }

    function _steps(bytes memory packed) internal pure returns (CertificateChecker.Step[] memory steps) {
        steps = new CertificateChecker.Step[](packed.length / 5);
        for (uint256 i = 0; i < steps.length; ++i) {
            uint256 o = i * 5;
            steps[i] = CertificateChecker.Step({
                left: uint32((uint256(uint8(packed[o])) << 8) | uint8(packed[o + 1])),
                right: uint32((uint256(uint8(packed[o + 2])) << 8) | uint8(packed[o + 3])),
                pivot: uint8(packed[o + 4])
            });
        }
    }

    function _sat(CertificateChecker.Clause memory c, uint256 assignment) internal pure returns (bool) {
        return (c.pos & assignment) | (c.neg & ~assignment) != 0;
    }

    // ---------------------------------------------------------------------------------------------
    // Satisfying assignments
    // ---------------------------------------------------------------------------------------------

    function test_WitnessAccepted() public view {
        // Two pigeons, two holes: pigeon 0 in hole 0 (variable 0), pigeon 1 in hole 1 (variable 3).
        assertTrue(checker.satisfies(_php(2, 2), 0x9));
        assertTrue(checker.satisfies(_php(2, 2), 0x6));
    }

    function test_WrongWitnessRefused() public view {
        // Both pigeons in hole 0.
        assertFalse(checker.satisfies(_php(2, 2), 0x5));
        // Pigeon 1 nowhere.
        assertFalse(checker.satisfies(_php(2, 2), 0x1));
        assertFalse(checker.satisfies(_php(2, 2), 0));
    }

    function test_EmptyFormulaIsSatisfied() public view {
        assertTrue(checker.satisfies(new CertificateChecker.Clause[](0), 0));
        assertEq(checker.countModels(new CertificateChecker.Clause[](0), 3), 8);
    }

    function test_CountModelsOfSquarePigeonholeIsFactorial() public view {
        assertEq(checker.countModels(_php(2, 2), 4), 2);
        assertEq(checker.countModels(_php(3, 3), 9), 6);
    }

    function test_CountModelsOfPigeonholeIsZero() public view {
        assertEq(checker.countModels(_php(2, 1), 2), 0);
        assertEq(checker.countModels(_php(3, 2), 6), 0);
        assertEq(checker.countModels(_php(4, 3), 12), 0);
    }

    function test_CountModelsRefusesTooManyVariables() public {
        CertificateChecker.Clause[] memory cnf = _php(2, 2);
        vm.expectRevert(abi.encodeWithSelector(CertificateChecker.TooManyVariables.selector, 21));
        checker.countModels(cnf, 21);
    }

    // ---------------------------------------------------------------------------------------------
    // Resolution refutations
    // ---------------------------------------------------------------------------------------------

    function test_RefutationOfPigeonhole_3_2() public view {
        assertTrue(checker.checkRefutation(_php(3, 2), _steps(PHP_3_2)));
    }

    function test_RefutationOfPigeonhole_4_3() public view {
        assertTrue(checker.checkRefutation(_php(4, 3), _steps(PHP_4_3)));
    }

    function test_RefutationOfPigeonhole_5_4() public view {
        CertificateChecker.Step[] memory steps = _steps(PHP_5_4);
        assertEq(steps.length, 377);
        assertTrue(checker.checkRefutation(_php(5, 4), steps));
    }

    function test_RefutationDoesNotTransferToAnotherFormula() public view {
        // The same steps against the satisfiable PHP(3, 3) must not be accepted: they either stop being
        // resolution steps or no longer end in the empty clause.
        CertificateChecker.Clause[] memory cnf = _php(3, 3);
        CertificateChecker.Step[] memory steps = _steps(PHP_3_2);
        try checker.checkRefutation(cnf, steps) returns (bool refuted) {
            assertFalse(refuted);
        } catch (bytes memory reason) {
            assertEq(bytes4(reason), CertificateChecker.PivotNotResolvable.selector);
        }
    }

    function test_TruncatedRefutationRefused() public view {
        CertificateChecker.Step[] memory full = _steps(PHP_4_3);
        CertificateChecker.Step[] memory cut = new CertificateChecker.Step[](full.length - 1);
        for (uint256 i = 0; i < cut.length; ++i) {
            cut[i] = full[i];
        }
        assertFalse(checker.checkRefutation(_php(4, 3), cut));
    }

    function test_WrongPivotReverts() public {
        CertificateChecker.Clause[] memory cnf = _php(3, 2);
        CertificateChecker.Step[] memory steps = _steps(PHP_3_2);
        // Clause 0 is x0 or x1: variable 5 is not in it.
        steps[0] = CertificateChecker.Step({left: 0, right: 3, pivot: 5});
        vm.expectRevert(abi.encodeWithSelector(CertificateChecker.PivotNotResolvable.selector, 0));
        checker.checkRefutation(cnf, steps);
    }

    function test_SwappedSidesRevert() public {
        CertificateChecker.Clause[] memory cnf = _php(3, 2);
        CertificateChecker.Step[] memory steps = _steps(PHP_3_2);
        (steps[0].left, steps[0].right) = (steps[0].right, steps[0].left);
        vm.expectRevert(abi.encodeWithSelector(CertificateChecker.PivotNotResolvable.selector, 0));
        checker.checkRefutation(cnf, steps);
    }

    function test_ForwardReferenceReverts() public {
        CertificateChecker.Clause[] memory cnf = _php(3, 2);
        CertificateChecker.Step[] memory steps = _steps(PHP_3_2);
        // Step 2 may use the formula's 9 clauses and the 2 derived before it, not itself.
        steps[2].left = uint32(cnf.length + 2);
        vm.expectRevert(abi.encodeWithSelector(CertificateChecker.StepOutOfRange.selector, 2));
        checker.checkRefutation(cnf, steps);
        steps[2].left = 0;
        steps[2].right = type(uint32).max;
        vm.expectRevert(abi.encodeWithSelector(CertificateChecker.StepOutOfRange.selector, 2));
        checker.checkRefutation(cnf, steps);
    }

    function test_NoStepsRefutesOnlyAnEmptyClause() public view {
        CertificateChecker.Step[] memory none = new CertificateChecker.Step[](0);
        assertFalse(checker.checkRefutation(_php(3, 2), none));
        assertFalse(checker.checkRefutation(new CertificateChecker.Clause[](0), none));
        CertificateChecker.Clause[] memory cnf = new CertificateChecker.Clause[](2);
        cnf[0] = CertificateChecker.Clause({pos: 1, neg: 0});
        assertTrue(checker.checkRefutation(cnf, none));
    }

    function test_UnitContradiction() public view {
        CertificateChecker.Clause[] memory cnf = new CertificateChecker.Clause[](2);
        cnf[0] = CertificateChecker.Clause({pos: uint256(1) << 255, neg: 0});
        cnf[1] = CertificateChecker.Clause({pos: 0, neg: uint256(1) << 255});
        CertificateChecker.Step[] memory steps = new CertificateChecker.Step[](1);
        steps[0] = CertificateChecker.Step({left: 0, right: 1, pivot: 255});
        assertTrue(checker.checkRefutation(cnf, steps));
        assertEq(checker.countModels(cnf, 0), 0);
    }

    /// @notice The case the fuzz test below found in an earlier version of the checker: `x or not x` and
    ///         `not x` are both true when x is false, so resolving them must not give the empty clause.
    function test_TautologyDoesNotRefute() public view {
        CertificateChecker.Clause[] memory cnf = new CertificateChecker.Clause[](2);
        cnf[0] = CertificateChecker.Clause({pos: 1, neg: 1});
        cnf[1] = CertificateChecker.Clause({pos: 0, neg: 1});
        CertificateChecker.Step[] memory steps = new CertificateChecker.Step[](1);
        steps[0] = CertificateChecker.Step({left: 0, right: 1, pivot: 0});
        assertTrue(checker.satisfies(cnf, 0));
        assertFalse(checker.checkRefutation(cnf, steps));
        CertificateChecker.Clause[] memory derived = checker.derive(cnf, steps);
        assertEq(derived[0].pos, 0);
        assertEq(derived[0].neg, 1);
        // Mirror image: `x or not x` on the right, `x` on the left, true when x is true.
        cnf[0] = CertificateChecker.Clause({pos: 1, neg: 0});
        cnf[1] = CertificateChecker.Clause({pos: 1, neg: 1});
        assertTrue(checker.satisfies(cnf, 1));
        assertFalse(checker.checkRefutation(cnf, steps));
    }

    /// @notice Soundness, tested: for a formula built to be true under `assignment`, every clause any valid
    ///         derivation produces is true under it too, so no derivation is accepted as a refutation.
    function testFuzz_NoRefutationOfSatisfiableFormula(uint256 seed, uint256 assignment) public view {
        uint256 numVars = 8;
        uint256 mask = (uint256(1) << numVars) - 1;
        assignment &= mask;
        CertificateChecker.Clause[] memory all = new CertificateChecker.Clause[](12 + 40);
        CertificateChecker.Clause[] memory cnf = new CertificateChecker.Clause[](12);
        for (uint256 i = 0; i < 12; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            // Sparse clauses, so that resolution has something to do.
            CertificateChecker.Clause memory c =
                CertificateChecker.Clause({pos: seed & (seed >> 8) & mask, neg: (seed >> 16) & (seed >> 24) & mask});
            if (!_sat(c, assignment)) {
                uint256 bit = uint256(1) << ((seed >> 32) % numVars);
                if (assignment & bit != 0) c.pos |= bit;
                else c.neg |= bit;
            }
            cnf[i] = c;
            all[i] = c;
        }
        CertificateChecker.Step[] memory buffer = new CertificateChecker.Step[](40);
        uint256 count;
        for (uint256 t = 0; t < 400 && count < 40; ++t) {
            seed = uint256(keccak256(abi.encode(seed, t)));
            uint256 left = seed % (12 + count);
            uint256 right = (seed >> 64) % (12 + count);
            uint256 pivot = (seed >> 128) % numVars;
            uint256 bit = uint256(1) << pivot;
            if (all[left].pos & bit == 0 || all[right].neg & bit == 0) continue;
            all[12 + count] = CertificateChecker.Clause({
                pos: (all[left].pos & ~bit) | all[right].pos, neg: all[left].neg | (all[right].neg & ~bit)
            });
            buffer[count++] = CertificateChecker.Step({left: uint32(left), right: uint32(right), pivot: uint8(pivot)});
        }
        CertificateChecker.Step[] memory steps = new CertificateChecker.Step[](count);
        for (uint256 i = 0; i < count; ++i) {
            steps[i] = buffer[i];
        }

        assertTrue(checker.satisfies(cnf, assignment));
        CertificateChecker.Clause[] memory derived = checker.derive(cnf, steps);
        assertEq(derived.length, count);
        for (uint256 i = 0; i < count; ++i) {
            assertEq(derived[i].pos, all[12 + i].pos);
            assertEq(derived[i].neg, all[12 + i].neg);
            assertTrue(_sat(derived[i], assignment));
        }
        assertFalse(checker.checkRefutation(cnf, steps));
    }

    /// @notice A witness and a refutation never coexist: whenever exhaustive counting finds a model, the
    ///         pigeonhole refutation steps are not accepted for that formula.
    function testFuzz_CountAgreesWithWitness(uint256 seed, uint256 assignment) public view {
        uint256 mask = 0x3f;
        assignment &= mask;
        CertificateChecker.Clause[] memory cnf = new CertificateChecker.Clause[](6);
        for (uint256 i = 0; i < 6; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            cnf[i] = CertificateChecker.Clause({pos: seed & mask, neg: (seed >> 8) & mask});
        }
        uint256 models = checker.countModels(cnf, 6);
        if (checker.satisfies(cnf, assignment)) assertGt(models, 0);
        if (models == 0) assertFalse(checker.satisfies(cnf, assignment));
        assertLe(models, 64);
    }
}
