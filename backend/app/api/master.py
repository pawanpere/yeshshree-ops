"""Master-data router (P10). Reads: any internal role. Writes: admin/planning.
Vendors use their own scoped endpoints (P37) — the vendor role gets 403 here.
NO delete routes anywhere (CLAUDE.md never-do: never delete master-data rows)."""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.deps import CurrentUser, require
from app.models.master import (Bom, BomLine, Customer, Line, LineMaterial, Material,
                               ProductionOrder, PurchaseOrder, Vendor)
from app.schemas import master as s
from app.services.master import apply_update, create_with_audit, get_or_404

router = APIRouter(prefix="/api/v1/master", tags=["master"])

INTERNAL = ("admin", "management", "planning", "plant_ops", "supervisor")
WRITERS = ("admin", "planning")

read_guard = require(*INTERNAL)
write_guard = require(*WRITERS)


# --- materials ---
@router.get("/materials", response_model=list[s.MaterialRead])
def list_materials(q: str | None = Query(None, description="search code/description"),
                   active_only: bool = True, limit: int = 200, offset: int = 0,
                   db: Session = Depends(get_db), _: CurrentUser = Depends(read_guard)):
    query = db.query(Material)
    if active_only:
        query = query.filter_by(is_active=True)
    if q:
        like = f"%{q}%"
        query = query.filter(Material.description.ilike(like) | Material.sap_code.ilike(like))
    return query.order_by(Material.sap_code).limit(limit).offset(offset).all()


@router.post("/materials", response_model=s.MaterialRead, status_code=201)
def create_material(body: s.MaterialCreate, db: Session = Depends(get_db),
                    user: CurrentUser = Depends(write_guard)):
    """Manual master add (§11.15): source='manual'; next SAP import adopts or flags it."""
    return create_with_audit(db, Material(**body.model_dump(), source="manual"),
                             user, "materials")


@router.patch("/materials/{material_id}", response_model=s.MaterialRead)
def update_material(material_id: int, body: s.MaterialUpdate,
                    db: Session = Depends(get_db),
                    user: CurrentUser = Depends(write_guard)):
    obj = get_or_404(db, Material, material_id, "material")
    apply_update(db, obj, body.model_dump(exclude_unset=True), user, "materials",
                 allowed={"description", "mat_group", "category", "uom", "price",
                          "abc", "is_active"})
    return obj


# --- vendors ---
@router.get("/vendors", response_model=list[s.VendorRead])
def list_vendors(q: str | None = None, active_only: bool = True,
                 limit: int = 200, offset: int = 0,
                 db: Session = Depends(get_db), _: CurrentUser = Depends(read_guard)):
    query = db.query(Vendor)
    if active_only:
        query = query.filter_by(is_active=True)
    if q:
        like = f"%{q}%"
        query = query.filter(Vendor.name.ilike(like) | Vendor.sap_code.ilike(like))
    return query.order_by(Vendor.name).limit(limit).offset(offset).all()


@router.post("/vendors", response_model=s.VendorRead, status_code=201)
def create_vendor(body: s.VendorCreate, db: Session = Depends(get_db),
                  user: CurrentUser = Depends(write_guard)):
    return create_with_audit(db, Vendor(**body.model_dump(), source="manual"),
                             user, "vendors")


@router.patch("/vendors/{vendor_id}", response_model=s.VendorRead)
def update_vendor(vendor_id: int, body: s.VendorUpdate, db: Session = Depends(get_db),
                  user: CurrentUser = Depends(write_guard)):
    """credit_limit / qty_limit_mt changes are money-affecting (playbook §7): allowed
    here for admin/planning but always audited; the re-baseline APPROVAL flow (M3)
    is the governed path for systematic changes."""
    obj = get_or_404(db, Vendor, vendor_id, "vendor")
    apply_update(db, obj, body.model_dump(exclude_unset=True), user, "vendors",
                 allowed={"name", "gstin", "phone", "city", "state", "credit_limit",
                          "qty_limit_mt", "is_active"})
    return obj


# --- lines ---
@router.get("/lines", response_model=list[s.LineRead])
def list_lines(db: Session = Depends(get_db), _: CurrentUser = Depends(read_guard)):
    lines = db.query(Line).order_by(Line.name).all()
    out = []
    for ln in lines:
        mats = [lm.material_id for lm in db.query(LineMaterial).filter_by(line_id=ln.id)]
        out.append(s.LineRead(id=ln.id, name=ln.name, plant=ln.plant,
                              is_active=ln.is_active, material_ids=mats))
    return out


@router.post("/lines", response_model=s.LineRead, status_code=201)
def create_line(body: s.LineCreate, db: Session = Depends(get_db),
                user: CurrentUser = Depends(write_guard)):
    ln = create_with_audit(db, Line(**body.model_dump()), user, "lines")
    return s.LineRead(id=ln.id, name=ln.name, plant=ln.plant,
                      is_active=ln.is_active, material_ids=[])


@router.patch("/lines/{line_id}", response_model=s.LineRead)
def update_line(line_id: int, body: s.LineUpdate, db: Session = Depends(get_db),
                user: CurrentUser = Depends(write_guard)):
    ln = get_or_404(db, Line, line_id, "line")
    apply_update(db, ln, body.model_dump(exclude_unset=True), user, "lines",
                 allowed={"name", "is_active"})
    mats = [lm.material_id for lm in db.query(LineMaterial).filter_by(line_id=ln.id)]
    return s.LineRead(id=ln.id, name=ln.name, plant=ln.plant,
                      is_active=ln.is_active, material_ids=mats)


@router.put("/lines/{line_id}/materials", response_model=s.LineRead)
def put_line_materials(line_id: int, body: s.LineMaterialsPut,
                       db: Session = Depends(get_db),
                       user: CurrentUser = Depends(write_guard)):
    from app.core.audit import record
    ln = get_or_404(db, Line, line_id, "line")
    current = {lm.material_id for lm in db.query(LineMaterial).filter_by(line_id=ln.id)}
    wanted = set(body.material_ids)
    for mid in wanted - current:
        get_or_404(db, Material, mid, "material")
        db.add(LineMaterial(line_id=ln.id, material_id=mid))
    for lm in db.query(LineMaterial).filter_by(line_id=ln.id):
        if lm.material_id not in wanted:
            db.delete(lm)  # mapping row, not master data — allowed
    if current != wanted:
        record(db, user_id=user.id, entity="line_materials", entity_id=ln.id,
               action="update", before={"material_ids": sorted(current)},
               after={"material_ids": sorted(wanted)})
    db.commit()
    return s.LineRead(id=ln.id, name=ln.name, plant=ln.plant,
                      is_active=ln.is_active, material_ids=sorted(wanted))


# --- production orders ---
@router.get("/production-orders", response_model=list[s.ProductionOrderRead])
def list_production_orders(line_id: int | None = None, db: Session = Depends(get_db),
                           _: CurrentUser = Depends(read_guard)):
    q = db.query(ProductionOrder)
    if line_id:
        q = q.filter_by(line_id=line_id)
    return q.order_by(ProductionOrder.sap_order_no).all()


@router.post("/production-orders", response_model=s.ProductionOrderRead, status_code=201)
def create_production_order(body: s.ProductionOrderCreate, db: Session = Depends(get_db),
                            user: CurrentUser = Depends(write_guard)):
    return create_with_audit(db, ProductionOrder(**body.model_dump()), user,
                             "production_orders")


@router.patch("/production-orders/{order_id}", response_model=s.ProductionOrderRead)
def update_production_order(order_id: int, body: s.ProductionOrderUpdate,
                            db: Session = Depends(get_db),
                            user: CurrentUser = Depends(write_guard)):
    obj = get_or_404(db, ProductionOrder, order_id, "production order")
    apply_update(db, obj, body.model_dump(exclude_unset=True), user,
                 "production_orders", allowed={"line_id", "material_id", "status"})
    return obj


# --- read-only: POs, BOMs, customers ---
@router.get("/purchase-orders", response_model=list[s.PurchaseOrderRead])
def list_purchase_orders(vendor_id: int | None = None, material_id: int | None = None,
                         status: str | None = "open", db: Session = Depends(get_db),
                         _: CurrentUser = Depends(read_guard)):
    q = db.query(PurchaseOrder)
    if vendor_id:
        q = q.filter_by(vendor_id=vendor_id)
    if material_id:
        q = q.filter_by(material_id=material_id)
    if status:
        q = q.filter_by(status=status)
    return q.order_by(PurchaseOrder.sap_po_no, PurchaseOrder.item_no).all()


@router.get("/boms", response_model=list[s.BomRead])
def list_boms(parent_material_id: int | None = None, db: Session = Depends(get_db),
              _: CurrentUser = Depends(read_guard)):
    q = db.query(Bom).filter_by(is_active=True)
    if parent_material_id:
        q = q.filter_by(parent_material_id=parent_material_id)
    out = []
    for bom in q.all():
        lines = db.query(BomLine).filter_by(bom_id=bom.id).order_by(BomLine.item_no).all()
        out.append(s.BomRead(id=bom.id, parent_material_id=bom.parent_material_id,
                             alt_bom=bom.alt_bom, is_active=bom.is_active,
                             lines=[s.BomLineRead.model_validate(l) for l in lines]))
    return out


@router.get("/customers", response_model=list[s.CustomerRead])
def list_customers(db: Session = Depends(get_db), _: CurrentUser = Depends(read_guard)):
    return db.query(Customer).order_by(Customer.name).all()
