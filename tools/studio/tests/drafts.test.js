'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { mergeDraft, locateAction } = require('../js/drafts.js');
test('a range-only old draft keeps fresh damage and unrelated new fields', () => {
  const conflicts = [];
  assert.deepEqual(mergeDraft({range:95,damage:7}, {range:96,damage:7}, {range:95,damage:12,new:true}, '', conflicts), {range:96,damage:12,new:true});
  assert.deepEqual(conflicts, []);
});
test('concurrent changes to the same field need an explicit choice', () => {
  const conflicts = [];
  assert.deepEqual(mergeDraft({damage:7}, {damage:8}, {damage:12}, '', conflicts), {damage:12});
  assert.deepEqual(conflicts, [{path:'damage',base:7,mine:8,latest:12}]);
});
test('particles and projectile style additions from other authors survive', () => {
  const base = {first:{color:'red'}}, mine = {first:{color:'brown'}}, latest = {...base,second:{new:true}};
  assert.deepEqual(mergeDraft(base,mine,latest), {first:{color:'brown'},second:{new:true}});
});
test('deleting a changed emitter is a conflict, not a silent deletion', () => {
  const conflicts = [];
  mergeDraft({frames:[1]}, undefined, {frames:[2]}, 'emitter', conflicts);
  assert.equal(conflicts.length, 1); assert.equal(conflicts[0].path, 'emitter');
});
test('independent fields in unchanged action lists compose', () => {
  const base = [{name:'Cry',type:'nova',damage:7,range:95}];
  assert.deepEqual(mergeDraft(base,[{...base[0],range:96}],[{...base[0],damage:12}]), [{...base[0],range:96,damage:12}]);
});
test('named actions survive reordering and ambiguous unnamed edits stop', () => {
  const base = [{name:'Cry',type:'nova',damage:7},{name:'Claw',type:'melee',damage:8}];
  assert.equal(locateAction([{...base[1]},{...base[0],damage:12}],base[0],0,base),1);
  assert.throws(() => locateAction([{type:'melee',damage:5}],{type:'nova',damage:7},0,[{type:'nova',damage:7}]), /неоднозначен/);
});
