classdef TestMotorScanJournal < matlab.unittest.TestCase
    properties
        Folder
    end
    methods(TestMethodSetup)
        function setup(t)
            t.Folder=tempname; mkdir(t.Folder);
            t.addTeardown(@()rmdir(t.Folder,'s'));
        end
    end
    methods(Test)
        function recordsAreReadableBeforeFinishAndRemainAfterFailure(t)
            j=MotorScanJournal(t.Folder,struct('PositionerMode','Hardware','VNAMode','Mock'));
            a=t.snapshot(0,359.9); b=t.snapshot(5,28.025);
            j.recordMove('AZ',5,a,b,'completed','','');
            j.recordMove('AZ',10,b,b,'failed','PositionerController:EncoderMismatch','short movement');
            rows=t.read(j.Path);
            t.verifyEqual(rows{1}.event,'scan_start');
            t.verifyEqual(rows{2}.event,'move_completed');
            t.verifyEqual(rows{3}.event,'move_failed');
            t.verifyEqual(rows{3}.error_id,'PositionerController:EncoderMismatch');
            t.verifyEqual(rows{3}.after.release_count,4);
            j.finish('ABORTED',1);
            rows=t.read(j.Path); t.verifyEqual(rows{end}.completed_points,1);
        end
        function fixedReferenceFindsIncreasingReturnDriftAcrossWrap(t)
            j=MotorScanJournal(t.Folder,struct('PositionerMode','Hardware','VNAMode','Mock'));
            a=t.snapshot(5,28); b=t.snapshot(0,0.1);
            r=j.recordMove('AZ',0,a,b,'completed','','');
            t.verifyEqual(r.error_antenna_deg,0.2/5.625,'AbsTol',1e-10);
            t.verifyFalse(r.warning);
            b.pan_encoder_deg=6;
            r=j.recordMove('AZ',0,a,b,'completed','','');
            t.verifyEqual(r.error_antenna_deg,6.1/5.625,'AbsTol',1e-10);
            t.verifyTrue(r.warning);
            b.pan_encoder_deg=12;
            r=j.recordMove('AZ',0,a,b,'completed','','');
            t.verifyEqual(r.error_antenna_deg,12.1/5.625,'AbsTol',1e-10);
        end
        function fullAntennaTurnIsNotMistakenForShaftZero(t)
            j=MotorScanJournal(t.Folder,struct('PositionerMode','Hardware','VNAMode','Mock'));
            a=t.snapshot(355,196.775); b=t.snapshot(360,224.9);
            r=j.recordMove('AZ',360,a,b,'completed','','');
            t.verifyEmpty(r);
            rows=t.read(j.Path); t.verifyNumElements(rows,2);
        end
        function missingReferenceAndFailedZeroMoveNeverClaimClosure(t)
            j=MotorScanJournal(t.Folder,struct('PositionerMode','Hardware','VNAMode','Mock'));
            a=t.snapshot(5,28); b=t.snapshot(0,0.1); b.pan_zero_encoder_deg=NaN;
            r=j.recordMove('AZ',0,a,b,'completed','','');
            t.verifyFalse(r.valid); t.verifyFalse(r.warning);
            r=j.recordMove('AZ',0,a,b,'failed','test:error','failed');
            t.verifyEmpty(r);
        end
        function filesAreUniqueAndMockUnitsAreExplicit(t)
            meta=struct('PositionerMode','Mock','VNAMode','Mock');
            j=MotorScanJournal(t.Folder,meta); k=MotorScanJournal(t.Folder,meta);
            t.verifyNotEqual(j.Path,k.Path);
            a=t.snapshot(5,184.9); b=t.snapshot(0,1.1);
            r=j.recordMove('AZ',0,a,b,'completed','','');
            t.verifyEqual(r.error_antenna_deg,1.2,'AbsTol',1e-10);
            rows=t.read(j.Path); t.verifyEqual(rows{1}.encoder_degrees_per_antenna_degree,1);
        end
        function closureRequiresUnchangedValidReferenceAndActiveHold(t)
            j=MotorScanJournal(t.Folder,struct('PositionerMode','Hardware','VNAMode','Mock'));
            a=t.snapshot(5,28); b=t.snapshot(0,0.1); b.pan_zero_id='replacement';
            r=j.recordMove('AZ',0,a,b,'completed','',''); t.verifyFalse(r.valid);
            b=t.snapshot(0,0.1); b.holding_active=false;
            r=j.recordMove('AZ',0,a,b,'completed','',''); t.verifyFalse(r.valid);
            b=t.snapshot(0,0.1); b.pan_zero_encoder_deg=-1;
            r=j.recordMove('AZ',0,a,b,'completed','',''); t.verifyFalse(r.valid);
        end
    end
    methods(Static)
        function s=snapshot(pan,encoder)
            s=struct('pan_deg',pan,'tilt_deg',85,'pan_encoder_deg',encoder, ...
                'tilt_encoder_deg',191.6,'holding_active',true,'is_homed',true, ...
                'manual_homing_active',false,'release_count',4, ...
                'pan_zero_encoder_deg',359.9,'pan_zero_id','fixed-zero');
        end
        function rows=read(path)
            lines=splitlines(strtrim(fileread(path)));
            rows=cellfun(@jsondecode,cellstr(lines),'UniformOutput',false);
        end
    end
end
