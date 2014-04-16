/* UV Editor */

/* exported init, clear, restart */

//XXX "use strict";

var container;
var canvas;
var ctx;
var img;
var update_uvs;
var update_selection;

var uvs;			// Input from SketchUp
var polys;			// Input from SketchUp - indices into uvs

var selection = {};		// indices into uvs
var selection_is_temporary;	// selection should be reset after operation
var saved_uvs;

var modes = { SELECT:0, MOVE:1, ROTATE:2, SCALE:3 };
var mode = modes.SELECT;
var scale = 1.0;
var zoomcumulative = 0;
var off_u=0; var off_v=0;	// Texture display offset in pixels (unscaled)
var dragstart;			// start of operation in canvas units

var point_u; var point_s;	// Unselected, selected, dragstart ImageData

var selectfudge = 3.5;		// cursor hotspot semi-width
var mouse_suppress_dupes;

// uv rounding for comparison
var uvRound = 8;
var uvFactor = Math.pow(10,uvRound);
var uvInverse = 1/uvFactor;


// Called after DOM inititialised. Not called under IE<9 since DOMContentLoaded not supported.
function init()
{
    // console.log("init");
    container = document.getElementById("container");
    canvas = document.getElementById("thecanvas");
    ctx = canvas.getContext("2d");
    img = document.getElementById("thetexture");
    update_uvs = document.getElementById("update_uvs");
    update_selection = document.getElementById("update_selection");
    point_u = make_point(ctx, 3, [0,0,0]);
    point_s = make_point(ctx, 5, [0,0,255]);
    window.addEventListener("resize", redraw, false);	// update on resize
    canvas.addEventListener("mousedown", on_mousedown, false);
    canvas.addEventListener('mousemove', on_mousemove, false);
    canvas.addEventListener("mouseup", on_mouseup, false);
    canvas.addEventListener("mousewheel", on_mousewheel, false);	// Safari 5 doesn't support "wheel"
    document.onkeydown = on_keydown;					// capture Enter & Esc
    document.addEventListener("keypress", on_keypress, false);
    // XXX document.oncontextmenu = function () { return false; };		// disable context menu
    window.location="skp:on_load";	// tell SketchUp to complete initialisation
}


function make_point(ctx, size, rgb)
{
    var imgData = ctx.createImageData(size,size);
    for (var i=0; i<imgData.data.length; i+=4)
    {
        imgData.data[i+0] = rgb[0];
        imgData.data[i+1] = rgb[1];
        imgData.data[i+2] = rgb[2];
        imgData.data[i+3] = 255;
    }
    return imgData;
}


function change_mode(newmode)
{
    mode = newmode;
    switch (mode)
    {
    case modes.MOVE:
        document.getElementById('tb-move').checked = true;
        document.getElementById('sb-info').innerHTML = (!Object.keys(selection).length ? "Use Select tool, or pick one UV to move." : "Pick two points to move. Shift = snap to pixels.");
        canvas.style.cursor = "url('./cursor_Move.png') 14 14, move";
        break;
    case modes.ROTATE:
        document.getElementById('tb-rotate').checked = true;
        document.getElementById('sb-info').innerHTML = "Pick rotation origin and angle. Shift = snap angle.";
        canvas.style.cursor = "url('./cursor_Rotate.png') 11 19, all-scroll";
        break;
    case modes.SCALE:
        document.getElementById('tb-scale').checked = true;
        document.getElementById('sb-info').innerHTML = "Pick scale origin and size.";
        canvas.style.cursor = "url('./cursor_Scale.png') 9 9, nesw-resize";
        break;
    default:
        document.getElementById('tb-select').checked = true;
        document.getElementById('sb-info').innerHTML = (uvs ? "Select UVs. Shift to extend select. Drag mouse to select multiple." : "Select Face(s) in the main window.");
        canvas.style.cursor = "auto";
    }

    // cancel any ongoing operation
    if (dragstart) window.location="skp:on_cancelupdate";
    dragstart = undefined;
    if (saved_uvs)
    {
        uvs = saved_uvs;
        saved_uvs = undefined;
    }
    document.getElementById('sb-input').value = "";
    document.getElementById('sb-input').disabled = true;
    document.getElementById('sb-label').innerHTML = "Measurements";

    redraw();
}


// Mouse interation
//
// In SELECT mode:
//  button dn: click, or drag selection area from dragstart
//  button up: display crosshair if hovering over a point
// Other modes w/out selection:
//  button dn: nothing
//  button up: highlight point if hovering over a point
// Other modes with selection:
//  button dn: perform operation with origin at dragstart
//  button up: if dragstart, perform operation with origin at dragstart
//  button up: if !dragstart, nothing


function on_keydown(e)
{
    // console.log('keydown',e.key,e.char,e.charCode,e.keyCode,e.metaKey,e.ctrlKey);
    if (e.keyCode == 13)
    {
        e.stopPropagation();
        return false;
    }
    else if (e.keyCode == 27)
    {
        change_mode(mode);	// Cancel any operation
        e.stopPropagation();
        return false;
    }
    return true;
}


function on_keypress(e)
{
    // console.log('keypress',e.key,e.char,e.charCode,e.keyCode,e.metaKey,e.ctrlKey);
    var c = String.fromCharCode(e.charCode);
    if (c==" " || (c=="/" && e.metaKey))
        change_mode(modes.SELECT);
    else if ((c=="m" || c=="M" || (c=="0" && e.metaKey)) && !document.getElementById('tb-move').disabled)
        change_mode(modes.MOVE);
    else if ((c=="q" || c=="Q" || (c=="8" && e.metaKey)) && !document.getElementById('tb-rotate').disabled)
        change_mode(modes.ROTATE);
    else if ((c=="s" || c=="S" || (c=="9" && e.metaKey)) && !document.getElementById('tb-scale').disabled)
        change_mode(modes.SCALE);
}


function on_mousedown(e)
{
    if (e.button || !uvs || !uvs.length) return false;
    // console.log('mousedown',e.clientX+","+e.clientY,e.button,dragstart,Object.keys(selection).length);

    var cursor = event2canvas(e);

    if (mode == modes.SELECT)
    {
        dragstart = cursor;
    }
    else if (!dragstart)
    {
        if (Object.keys(selection).length)
        {
            document.getElementById('sb-input').disabled = false;
            switch (mode)
            {
            case modes.MOVE:
                document.getElementById('sb-label').innerHTML = "Pixels";
                break;
            case modes.ROTATE:
                document.getElementById('sb-label').innerHTML = "Angle";
                break;
            case modes.SCALE:
                document.getElementById('sb-label').innerHTML = "Scale";
                break;
            }
            saved_uvs = uvs;
            dragstart = cursor;
            mouse_suppress_dupes = cursor;	// suppress mouse movement after mouse down
            // console.log('start');
            window.location="skp:on_startupdate";
            redraw();
        }
        else		// can move points without prior selection
        {
            var hits = uvs_at(cursor);
            if (hits.length)
            {
                for (var i=0; i<hits.length; i++)
                    selection[hits[i]] = true;	// latch selection
                selection_is_temporary = true;
                document.getElementById('sb-info').innerHTML = "Pick point to move. Shift = snap to pixels.";
                document.getElementById('sb-input').disabled = false;
                document.getElementById('sb-label').innerHTML = "Pixels";
                saved_uvs = uvs;
                dragstart = uv2canvas(uvs[hits[0]]);
                // snap to selection average - doesn't work because mouse up detects the offset as a move
                // var coords = Object.keys(selection).map(function(idx) { return uvs[idx]; });
                // var uv = coords.reduce(function(a,b) { return [a[0]+b[0], a[1]+b[1]]; });
                // dragstart = uv2canvas([uv[0] / coords.length, uv[1] / coords.length]); 
                mouse_suppress_dupes = cursor;	// suppress mouse movement after mouse down
                // console.log('start', dragstart);
                window.location="skp:on_startupdate";
                redraw();
            }
        }
    }
}


function on_mousemove(e)
{
    if (!uvs || !uvs.length) return;
    var cursor = event2canvas(e);
    if (mouse_suppress_dupes && mouse_suppress_dupes[0]==cursor[0] && mouse_suppress_dupes[1]==cursor[1]) return;

    // console.log('mousemove',cursor);
    if (mode == modes.SELECT)
    {
        if (dragstart)
        {
            selection = uvs_within(dragstart, cursor);
            redraw();
            // move origin to make the dotted line look better. Assumes that this is the last thing we draw
            ctx.translate(Math.round(dragstart[0]-0.5)+0.5, Math.round(dragstart[1]-0.5)+0.5);
            draw_dotted_h(ctx, 0, 0, Math.round(cursor[0]-dragstart[0]));
            draw_dotted_h(ctx, Math.round(cursor[1]-dragstart[1]), 0, Math.round(cursor[0]-dragstart[0]));
            draw_dotted_v(ctx, 0, 0, Math.round(cursor[1]-dragstart[1]));
            draw_dotted_v(ctx, Math.round(cursor[0]-dragstart[0]), 0, Math.round(cursor[1]-dragstart[1]));
        }
        else
        {
            draw_selected_at(cursor);
        }
    }
    else if (!Object.keys(selection).length)	// active mode with no pre-selection
    {
        draw_hover_at(cursor);
    }
    else if (dragstart && (Math.abs(cursor[0]-dragstart[0])>selectfudge || Math.abs(cursor[1]-dragstart[1])>selectfudge))	// active mode
    {
        uvs = saved_uvs.slice(0);	// restore so don't inference with dragged point at cursor
        var hits = uvs_at(cursor);	// inference
        if (hits.length)
        {
            cursor = uv2canvas(uvs[hits[0]]);	// snap
            apply(cursor);
            redraw();
            draw_inference(cursor);
        }
        else
        {
            apply(cursor, e.shiftKey);
            redraw();
        }
        // rotate to make the dotted line look better. Assumes that this is the last thing we draw
        var delta = [cursor[0]-dragstart[0], cursor[1]-dragstart[1]];
        ctx.translate(Math.round(dragstart[0]-0.5)+0.5, Math.round(dragstart[1]-0.5)+0.5);
        ctx.rotate(Math.atan2(delta[1],delta[0]));
        draw_dotted_h(ctx, 0, 0, Math.sqrt(delta[0]*delta[0] + delta[1]*delta[1]));
    }
    else if (dragstart)	// active mode but too close to origin
    {
        uvs = saved_uvs.slice(0);	// restore
        redraw();
    }
    else	// active mode with selection but no origin yet
    {
        draw_inference_at(cursor);
    }
}


function on_mouseup(e)
{
    if (!uvs || !uvs.length) return;
    var cursor = event2canvas(e);
    var hits;
    var moved = (dragstart && (Math.abs(cursor[0]-dragstart[0])>selectfudge || Math.abs(cursor[1]-dragstart[1])>selectfudge));
    //console.log('mouseup',e.clientX+","+e.clientY, e.button, e.shiftKey, dragstart, moved)

    if (mode == modes.SELECT)
    {
        var i;
        if (moved)
        {
            selection = uvs_within(dragstart, cursor);
        }
        else if (!e.shiftKey)	// click
        {
            hits = uvs_at(cursor);
            selection = {};
            for (i=0; i<hits.length; i++)
                selection[hits[i]] = true;
        }
        else
        {
            hits = uvs_at(cursor);
            for (i=0; i<hits.length; i++)
            {
                if (selection[hits[i]])
                    delete selection[hits[i]];
                else
                    selection[hits[i]] = true;
            }
        }
        dragstart = undefined;
        selection_is_temporary = false;
    }
    else if (mouse_suppress_dupes && mouse_suppress_dupes[0]==cursor[0] && mouse_suppress_dupes[1]==cursor[1])
        return;
    else if (Object.keys(selection).length)	// active mode
    {
        if (moved)
        {
            uvs = saved_uvs.slice(0);		// copy
            hits = uvs_at(cursor);		// inference
            if (hits.length)
            {
                cursor = uv2canvas(uvs[hits[0]]);	// snap
                apply(cursor);
            }
            else
                apply(cursor, e.shiftKey);
            mouse_suppress_dupes = cursor;	// suppress mouse movement after mouse down
            window.location="skp:on_finishupdate";
        }
        else
        {
            window.location="skp:on_cancelupdate";
        }
        document.getElementById('sb-input').value = "";
        document.getElementById('sb-input').disabled = true;
        document.getElementById('sb-label').innerHTML = "Measurements";
        dragstart = undefined;
        saved_uvs = undefined;
        if (selection_is_temporary) selection = {};
    }
    // preserve dragstart if clicked to start active mode

    redraw();
}


// draw a horizontal dotted line
function draw_dotted_h(ctx, y, x_start, x_end)
{
    if (x_start>x_end) x_start = x_end + (x_end=x_start, 0);	// swap
    ctx.strokeStyle = "White";
    ctx.beginPath();
    ctx.moveTo(x_start,y);
    ctx.lineTo(x_end, y);
    ctx.stroke();
    ctx.strokeStyle = "Black";
    ctx.beginPath();
    for (var x=x_start-0.5; x<x_end; x+=4)
    {
        ctx.moveTo(x,y);
        ctx.lineTo(Math.min(x+2, x_end), y);
    }
    ctx.stroke();
}


// draw a vertical dotted line
function draw_dotted_v(ctx, x, y_start, y_end)
{
    if (y_start>y_end) y_start = y_end + (y_end=y_start, 0);	// swap
    ctx.strokeStyle = "White";
    ctx.beginPath();
    ctx.moveTo(x, y_start);
    ctx.lineTo(x, y_end);
    ctx.stroke();
    ctx.strokeStyle = "Black";
    ctx.beginPath();
    for (var y=y_start-0.5; y<y_end-2; y+=4)
    {
        ctx.moveTo(x,y);
        ctx.lineTo(x,Math.min(y+2, y_end));
    }
    ctx.stroke();
}


// apply current operation
function apply(cursor, snap)
{
    function uvs_move(idx)
    {
        var uv = uvs[idx];
        uvs[idx] = snap ? uvround([Math.round((uv[0] + uvdelta[0]) * img.naturalWidth) / img.naturalWidth, 
                                   Math.round((uv[1] + uvdelta[1]) *img.naturalHeight) / img.naturalHeight]) :
            [uv[0] + uvdelta[0], uv[1] + uvdelta[1]];            
    }

    function uvs_rotate(idx)
    {
        var uv = uvs[idx];
        var uvdelta = [uv[0]-origin[0], uv[1]-origin[1]];
        var uvangle = Math.atan2(uvdelta[1], uvdelta[0]);
        var uvhypot = Math.sqrt(uvdelta[1]*uvdelta[1], uvdelta[0]*uvdelta[0]);
        uvs[idx] = uvround([origin[0] + Math.cos(angle+uvangle) * uvdelta[0], origin[1] - Math.sin(angle+uvangle) * uvdelta[1]]);
        // console.log(origin, uvdelta, uvangle, uvhypot, uvs[idx]);
    }

    switch (mode)
    {
    case modes.MOVE:
        var uvdelta = uvround([(cursor[0]-dragstart[0])/scale/img.naturalWidth,
                               (dragstart[1]-cursor[1])/scale/img.naturalHeight]);	// canvas origin is top, uv orgin bottom
        document.getElementById('sb-input').value = snap ?
            Math.round(uvdelta[0]*img.naturalWidth) + ', ' + Math.round(uvdelta[1]*img.naturalWidth) :
            (uvdelta[0]*img.naturalWidth).toPrecision(6) + ', ' + (uvdelta[1]*img.naturalWidth).toPrecision(6);
        Object.keys(selection).forEach(uvs_move);
        // console.log("move", cursor, dragstart, [cursor[0]-dragstart[0], cursor[1]-dragstart[1]], uvdelta, saved_uvs[Object.keys(selection)[0]], uvs[Object.keys(selection)[0]]);
        break;

    case modes.ROTATE:
        if (Math.abs(cursor[0]-dragstart[0])>selectfudge || Math.abs(cursor[1]-dragstart[1])>selectfudge)
        {
            var angle = Math.atan2(cursor[1]-dragstart[1], cursor[0]-dragstart[0]);
            var origin = canvas2uv(dragstart);
            if (snap) angle = Math.round(angle * 12/Math.PI) * Math.PI/12;	// round to nearest 15 degrees
            // console.log(angle, angle * 180/Math.PI);
            document.getElementById('sb-input').value = snap ? Math.round(angle * 180/Math.PI) : (angle * 180/Math.PI).toPrecision(4); // XXX Math.abs(angle)
            Object.keys(selection).forEach(uvs_rotate);
        }
        else
            document.getElementById('sb-input').value = "0";
        break;
    }
    var changed_indices = Object.keys(selection);
    update_selection.value = '['+changed_indices+']';
    var changed_uvs = [];
    for (var i=0; i<changed_indices.length; i++)
        changed_uvs.push(uvs[changed_indices[i]]);
    update_uvs.value = '[['+changed_uvs.join('],[')+']]';
    window.location="skp:on_update";
}


// returns *list* of selected uv indices. First item is one of the UVs under the cursor.
function uvs_at(cursor)
{
    function poly_selectnode(i) 
    {
        if (!primary[i]) secondary[i] = true;
    }

    function poly_selectcomplex(poly)
    {
        if (poly.length>4 && poly.indexOf(idx)>=0)
            poly.forEach(poly_selectnode);
    }

    var primary = {};
    var secondary = {};
    for (var idx=0; idx<uvs.length; idx++)
    {
        var uvc = uv2canvas(uvs[idx]);
        if (Math.abs(cursor[0]-uvc[0])<=selectfudge && Math.abs(cursor[1]-uvc[1])<=selectfudge)
        {
            primary[idx] = true;
            polys.forEach(poly_selectcomplex);	// also select neighbours in complex polygons
        }
    }

    return Object.keys(primary).concat(Object.keys(secondary));
}


function uvs_within(pta, ptb)
{
    function poly_selectnode(i) 
    {
        newsel[i] = true;
    }

    function poly_selectcomplex(poly)
    {
        if (poly.length>4 && poly.indexOf(idx)>=0)
            poly.forEach(poly_selectnode);
    }

    var min = [Math.min(pta[0],ptb[0])-selectfudge, Math.min(pta[1],ptb[1])-selectfudge];
    var max = [Math.max(pta[0],ptb[0])+selectfudge, Math.max(pta[1],ptb[1])+selectfudge];
    var newsel = {};
    for (var idx=0; idx<uvs.length; idx++)
    {
        var uvc = uv2canvas(uvs[idx]);
        if (min[0] <= uvc[0] && uvc[0] <= max[0] && min[1] <= uvc[1] && uvc[1] <= max[1])
        {
            newsel[idx] = true;
            polys.forEach(poly_selectcomplex);	// also select neighbours in complex polygons
        }
    }
    return newsel;
}


function on_mousewheel(e)
{
    e.stopPropagation();

    // need to keep the pixel under the cursor under the cursor
    var cursor = event2canvas(e);
    var u = cursor[0]/scale - off_u;
    var v = cursor[1]/scale - off_v;
    var oldscale = scale;
    // console.log(e.wheelDelta,cursor[0]+","+cursor[1],scale,u+","+v,off_u+","+off_v);

    zoomcumulative += e.wheelDelta;
    while (zoomcumulative >= 120)
    {
        zoomcumulative -= 120;
        if (scale<32)	// arbitrary limit
            scale *= Math.sqrt(2);
        else
            scale = 32;
    }
    while (zoomcumulative <= -120)
    {
        zoomcumulative += 120;
        if (scale>1/32)	// arbitrary limit
            scale *= 1/Math.sqrt(2);
        else
            scale = 1/32;
    }

    if (scale>=0.99 && scale<=1.01) scale=1;	// correct rounding when we pass unit scale
    if (scale!=oldscale)
    {
        off_u = Math.round(cursor[0]/scale - u);	// cleaner texture and lines if we use integer offsets
        off_v = Math.round(cursor[1]/scale - v);	// and doesn't noticably affect acccuracy of zooming
        redraw();
    }

    return false;		// defeat the scrollbars that we shouldn't have :)
}


function clear()
{
    // console.log("clear");
    if (!container) init();	// for some reason DOMContentLoaded didn't fire
    selection = {};
    uvs = undefined;
    polys = undefined;
    saved_uvs = undefined;
    change_mode(modes.SELECT);	// cancel any ongoing operation
    document.getElementById('tb-select').disabled = document.getElementById('tb-move').disabled = document.getElementById('tb-rotate').disabled = document.getElementById('tb-scale').disabled = true;
}


// New set of polygons from SketchUp
function restart()
{
    // console.log("restart");
    if (!container) init();	// for some reason DOMContentLoaded didn't fire
    selection = {};
    saved_uvs = undefined;
    change_mode(modes.SELECT);	// cancel any ongoing operation
    document.getElementById('tb-select').disabled = document.getElementById('tb-move').disabled = false;
}


function redraw()
{
    function poly_draw(poly)
    {
        for (var i=0; i<poly.length; i++)
        {
            var grad;
            var uva = poly[i];
            var uvca = uv2canvas(uvs[uva]);
            var uvb = poly[i+1==poly.length ? 0 : i+1];	// wrap round to first
            var uvcb = uv2canvas(uvs[uvb]);

            if (selection[uva] && selection[uvb])
                ctx.strokeStyle = "Blue";
            else if (selection[uva] && !selection[uvb])
            {
                grad = ctx.createLinearGradient(uvca[0], uvca[1], uvcb[0], uvcb[1]);
                grad.addColorStop(0, "Blue");
                grad.addColorStop(1, "White");
                ctx.strokeStyle = grad;
            }
            else if (!selection[uva] && selection[uvb])
            {
                grad = ctx.createLinearGradient(uvca[0], uvca[1], uvcb[0], uvcb[1]);
                grad.addColorStop(0, "White");
                grad.addColorStop(1, "Blue");
                ctx.strokeStyle = grad;
            }
            else
                ctx.strokeStyle = "White";

            ctx.beginPath();
            ctx.moveTo(uvca[0], uvca[1]);
            ctx.lineTo(uvcb[0], uvcb[1]);
            ctx.stroke();
        }
    }

    // console.log(container.clientWidth+","+container.clientHeight);
    canvas.style.width = canvas.width = container.clientWidth;
    canvas.style.height = canvas.height = container.clientHeight;

    if (!uvs || !uvs.length) return;

    // Can't scale the context since that messes up line widths. So do all scaling by hand.

    // Draw dimmed repetitions of the texture
    for (var u = -Math.ceil(off_u/img.naturalWidth)*img.naturalWidth; (off_u+u)*scale<canvas.width; u+=img.naturalWidth)
        for (var v = -Math.ceil(off_v/img.naturalHeight)*img.naturalHeight; (off_v+v)*scale<canvas.height; v+=img.naturalHeight)
            ctx.drawImage(img, (off_u+u)*scale, (off_v+v)*scale, img.naturalWidth*scale, img.naturalHeight*scale);
    ctx.fillStyle = "rgba(0, 0, 0, 0.2)";
    ctx.fillRect (0, 0, canvas.width, canvas.height);

    // Draw the texture
    ctx.drawImage(img, off_u*scale, off_v*scale, img.naturalWidth*scale, img.naturalHeight*scale);

    // Draw lines
    ctx.lineWidth = 1;
    ctx.shadowBlur = 3;
    ctx.shadowColor = "Black";
    polys.forEach(poly_draw);

    // Draw points
    ctx.shadowBlur = 0;
    ctx.shadowColor = "transparent";
    for (var i=0; i<uvs.length; i++)
        draw_point(uv2canvas(uvs[i]), selection[i] ? point_s : point_u);
}


function draw_inference(cursor)
{
    ctx.strokeStyle = "ForestGreen";
    ctx.fillStyle = "rgba(50, 205, 50, 0.9)";	// LimeGreen
    ctx.beginPath();
    ctx.arc(cursor[0], cursor[1], 3.5, 0, 2*Math.PI);
    ctx.fill();
    ctx.stroke();
}


function draw_inference_at(cursor)
{
    redraw();
    var hits = uvs_at(cursor);
    if (hits.length)
        draw_inference(uv2canvas(uvs[hits[0]]));
    return hits;
}


function draw_point(cursor, point)
{
    ctx.putImageData(point, Math.round(cursor[0]-point.width/2), Math.round(cursor[1]-point.height/2));
}


function draw_selected_at(cursor)
{
    redraw();
    var hits = uvs_at(cursor);
    if (hits.length)
        draw_point(uv2canvas(uvs[hits[0]]), point_s);
    return hits;
}


function draw_hover_at(cursor)
{
    var hits = uvs_at(cursor);
    if (hits.length)
    {
        var saved = Object.keys(selection);
        for (var i=0; i<hits.length; i++)
            selection[hits[i]] = true;
        redraw();
        // restore selection
        selection = {};
        for (i=0; i<saved.length; i++)
            selection[saved[i]] = true;
        draw_inference(uv2canvas(uvs[hits[0]]));
    }
    else
        redraw();
}


// convert event coordinate to canvas coordinate
function event2canvas(e)
{
    var rect = canvas.getBoundingClientRect();
    return([e.clientX - rect.left, e.clientY - rect.top]);
}

// convert uv coordinate to canvas coordinate
function uv2canvas(uv)
{
    return [(off_u + uv[0]*img.naturalWidth)*scale, (off_v + img.naturalHeight - uv[1]*img.naturalHeight)*scale];
}

// convert canvas coordinate to uv (rounded)
function canvas2uv(coord)
{
    return uvround([(coord[0]/scale - off_u) / img.naturalWidth, (off_v + img.naturalHeight - coord[1]/scale) / img.naturalHeight]);
}

function uvround(uv)
{
    return [Math.round(uv[0]*uvFactor) * uvInverse, Math.round(uv[1]*uvFactor) * uvInverse];
}